# 002 · Juicy Mac — реализация v1

Дата: 2026-09-21 · Основа: [001 · концепция](../001-juicy-mac-concept/README.md) · Дизайн: https://claude.ai/artifact/SLGSGayiLK3m83aHHiDpqp

## Цель

Нативное menubar-приложение для macOS 26+, в котором работает всё, что нарисовано в дизайне:
иконка в menubar (5 стилей), popover, окно с модулями, управление вентиляторами, правила-тревоги, вкусы.

Сверх дизайна в v1 добавлено:

| Функция | Зачем |
|---|---|
| Модуль **Network** | скорость приёма и отдачи, история |
| Модуль **GPU** (в CPU-экране и Overview) | загрузка GPU из `IOAccelerator` |
| **Энергопотребление** | мощность системы (`PSTR` из SMC), мощность адаптера |
| **Squeeze test** | 30-секундный стресс-тест: пик температуры, обороты, мощность, оценка охлаждения A–D |
| **Уведомления** | правила Alerts шлют системные уведомления |
| **Quit process** | завершение прожорливого процесса из popover и Overview |
| **История 24 ч** | диапазоны 1 мин / 15 мин / 1 ч / 24 ч |
| **Launch at login** | `SMAppService.mainApp` |

## Архитектура

```
JuicyMac.app (LSUIElement, menubar + окно)
├─ JuicyKit (локальный Swift-пакет)
│  ├─ CSMC            — C-обёртка над AppleSMC (IOConnectCallStructMethod, структура 80 байт)
│  ├─ JuicyCore       — чистая логика: модели, история, Juice score, правила, кривая вентиляторов, форматирование
│  ├─ JuicySystem     — сэмплеры: CPU, память, диск, сеть, батарея, GPU, датчики/вентиляторы (SMC), процессы
│  └─ JuicyHelperKit  — XPC-протокол и константы хелпера
└─ Contents/Library/LaunchDaemons/com.kovalskyi.JuicyMac.Helper.plist
   └─ JuicyMacHelper (root, SMAppService.daemon) — только запись SMC: режим и цель оборотов
```

Поток данных: `SamplingEngine` (actor) раз в 1 с (окно или popover открыты) или раз в 3 с (в фоне)
опрашивает сэмплеры и отдаёт `Snapshot` (Sendable). `AppModel` (@MainActor, @Observable) кладёт
снимок в историю, считает Juice score, прогоняет правила и управляет вентиляторами.

### Источники данных

| Метрика | API |
|---|---|
| CPU по ядрам | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, дельта тиков; P/E из `hw.perflevel*` |
| Память | `host_statistics64(HOST_VM_INFO64)`: Apps = internal − purgeable, Wired, Compressed, Cache = external + purgeable; `vm.swapusage`; `kern.memorystatus_vm_pressure_level` |
| Диск | `volumeAvailableCapacityForImportantUsage`; `IOBlockStorageDriver` → Statistics (Bytes Read/Write) |
| Сеть | `sysctl NET_RT_IFLIST2` → `if_data64` (64-битные счётчики), интерфейсы `en*` |
| Батарея | `IOPSCopyPowerSourcesInfo`, `AppleSmartBattery` (циклы, ёмкость, температура, напряжение, ток), `IOPSCopyExternalPowerAdapterDetails` |
| GPU | `IOAccelerator` → PerformanceStatistics → `Device Utilization %` |
| Температуры | перебор всех SMC-ключей `T*` типа `flt `, группировка по префиксу (Tp/Te/Tf — CPU, Tg — GPU, TB — батарея, TH/TN — SSD) |
| Вентиляторы | `FNum`, `F{i}Ac/Mn/Mx/Tg/Md` |
| Мощность | SMC `PSTR` (система), иначе напряжение × ток батареи |
| Процессы | `proc_listallpids` + `proc_pid_rusage(V2)`, время в mach-тиках → нс через `mach_timebase_info` |

### Вентиляторы и безопасность

- Приложение само ничего в SMC не пишет. Запись делает хелпер под root через XPC.
- Хелпер принимает соединения только от приложения с тем же Team ID (`setCodeSigningRequirement`).
- Цель оборотов зажимается в `[F{i}Mn, F{i}Mx]`. Если ключ `Ftst` существует (новые Apple Silicon), перед
  принудительным режимом пишется `Ftst = 1`, при возврате в Auto — `0`.
- Сторож: нет команд 30 с или клиент отключился — все вентиляторы в Auto.
- Режимы: **Auto** — сброс; **Blast** — максимум; **Chill** — цель 2 500 rpm, но при CPU ≥ 85°C сразу Auto;
  **Custom** — кривая «°C → rpm», приложение пересчитывает цель каждый тик.
- Без установленного хелпера модуль Fans работает только на чтение и предлагает установку
  (System Settings → Login Items).

## Juice score

`JuiceScore.compute(snapshot, sustained)` = 100 − штрафы, веса из концепции: нагрев 30, память 25,
CPU 20, диск 15, батарея 10. Штрафы за нагрев и CPU начисляются только за устойчивое состояние
(скользящее среднее за 60 с и 5 мин), разовые всплески оценку не портят.

## Правила (Alerts)

`AlertRule { metric, comparator, threshold, duration, actions }`. Метрики: температура CPU, загрузка CPU,
GPU, давление памяти, заряд, свободный диск. Действия: уведомление, Blast вентиляторов, красный стакан.
Правило срабатывает один раз, когда условие держится `duration` секунд, и сбрасывается, когда
значение уходит за порог с гистерезисом 3%.

## Тесты

`swift test` в `JuicyKit`: декодирование SMC-типов (flt, fpe2, sp78, ui8/16/32), дельты CPU, раскладка
памяти, счётчики сети, кольцевой буфер и даунсэмплинг, Juice score, движок правил, кривая вентиляторов.
Отдельные smoke-тесты запускают настоящие сэмплеры на этом Mac.

## Сборка

```
cd JuicyKit && swift test
xcodegen generate
xcodebuild -project JuicyMac.xcodeproj -scheme JuicyMac -sdk macosx -configuration Debug build
```

## Ограничения v1

- Частоты ядер не показываются: нужен приватный IOReport.
- Лимит заряда батареи (как в AlDente) — следующий этап, тоже через хелпер.
- Виджеты и App Intents — v1.x.
