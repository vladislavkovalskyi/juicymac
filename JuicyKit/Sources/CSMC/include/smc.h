// Minimal client for the AppleSMC IOKit user client.
// Reads work for any process; writes need root (the Juicy Mac helper).
#ifndef CSMC_SMC_H
#define CSMC_SMC_H

#include <stdint.h>
#include <stdbool.h>
#include <IOKit/IOKitLib.h>

typedef struct {
    uint32_t key;       // four-char code, e.g. 'F0Ac'
    uint32_t type;      // four-char code, e.g. 'flt '
    uint32_t size;      // payload size in bytes (<= 32)
    uint8_t attributes;
} smc_key_info_t;

typedef struct {
    smc_key_info_t info;
    uint8_t bytes[32];
} smc_value_t;

/// Opens a connection to AppleSMC. Returns kIOReturnSuccess and fills `conn`.
kern_return_t smc_open(io_connect_t *conn);
void smc_close(io_connect_t conn);

/// Key metadata (type and size). Fails with kIOReturnNotFound style codes when the key is absent.
kern_return_t smc_key_info(io_connect_t conn, uint32_t key, smc_key_info_t *info);

/// Reads a key's raw bytes.
kern_return_t smc_read(io_connect_t conn, uint32_t key, smc_value_t *value);

/// Writes raw bytes; `size` must match the key's size. Needs root.
kern_return_t smc_write(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size);

/// Key at position `index` in the SMC key table (0 ..< '#KEY').
kern_return_t smc_key_at_index(io_connect_t conn, uint32_t index, uint32_t *key);

#endif
