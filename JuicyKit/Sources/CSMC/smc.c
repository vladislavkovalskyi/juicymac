#include "smc.h"
#include <string.h>

// Layout of the struct the AppleSMC user client expects (80 bytes).
typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} smc_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} smc_plimit_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} smc_keyinfo_raw_t;

typedef struct {
    uint32_t key;
    smc_vers_t vers;
    smc_plimit_t pLimitData;
    smc_keyinfo_raw_t keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    uint8_t bytes[32];
} smc_param_t;

enum {
    kSMCUserClientIndex = 2,
    kSMCReadBytes = 5,
    kSMCWriteBytes = 6,
    kSMCReadIndex = 8,
    kSMCReadKeyInfo = 9,
};

_Static_assert(sizeof(smc_param_t) == 80, "AppleSMC expects an 80-byte parameter struct");

static kern_return_t smc_call(io_connect_t conn, smc_param_t *in, smc_param_t *out) {
    size_t outSize = sizeof(smc_param_t);
    kern_return_t kr = IOConnectCallStructMethod(conn, kSMCUserClientIndex, in, sizeof(smc_param_t), out, &outSize);
    if (kr != kIOReturnSuccess) return kr;
    // result != 0 means the SMC rejected the request (e.g. key not found = 132).
    if (out->result != 0) return kIOReturnError;
    return kIOReturnSuccess;
}

kern_return_t smc_open(io_connect_t *conn) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) return kIOReturnNotFound;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, conn);
    IOObjectRelease(service);
    return kr;
}

void smc_close(io_connect_t conn) {
    if (conn != IO_OBJECT_NULL) IOServiceClose(conn);
}

kern_return_t smc_key_info(io_connect_t conn, uint32_t key, smc_key_info_t *info) {
    smc_param_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = kSMCReadKeyInfo;
    kern_return_t kr = smc_call(conn, &in, &out);
    if (kr != kIOReturnSuccess) return kr;
    info->key = key;
    info->type = out.keyInfo.dataType;
    info->size = out.keyInfo.dataSize;
    info->attributes = (uint8_t)out.keyInfo.dataAttributes;
    return kIOReturnSuccess;
}

kern_return_t smc_read(io_connect_t conn, uint32_t key, smc_value_t *value) {
    memset(value, 0, sizeof(*value));
    kern_return_t kr = smc_key_info(conn, key, &value->info);
    if (kr != kIOReturnSuccess) return kr;
    if (value->info.size > 32) return kIOReturnBadArgument;

    smc_param_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.keyInfo.dataSize = value->info.size;
    in.data8 = kSMCReadBytes;
    kr = smc_call(conn, &in, &out);
    if (kr != kIOReturnSuccess) return kr;
    memcpy(value->bytes, out.bytes, value->info.size);
    return kIOReturnSuccess;
}

kern_return_t smc_write(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size) {
    smc_key_info_t info;
    kern_return_t kr = smc_key_info(conn, key, &info);
    if (kr != kIOReturnSuccess) return kr;
    if (info.size != size || size > 32) return kIOReturnBadArgument;

    smc_param_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = kSMCWriteBytes;
    in.keyInfo.dataSize = size;
    memcpy(in.bytes, bytes, size);
    return smc_call(conn, &in, &out);
}

kern_return_t smc_key_at_index(io_connect_t conn, uint32_t index, uint32_t *key) {
    smc_param_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.data8 = kSMCReadIndex;
    in.data32 = index;
    kern_return_t kr = smc_call(conn, &in, &out);
    if (kr != kIOReturnSuccess) return kr;
    *key = out.key;
    return kIOReturnSuccess;
}
