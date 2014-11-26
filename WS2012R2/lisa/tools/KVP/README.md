#/tools/KVP

The **/tools/KVP** directory contains the **kvp_client** utility for use on Linux VMs.  This tool will list the contents of the KVP pools, as well as allow new KVP items to be added to the KVP pools.  It is used by some of the LIS test cases.

To compile the **kvp_client.c** utility, you will need the following two .h files from the Linux kernel source tree:
```C
include/linux/hyperv.h
include/uapi/linux/connector.h
```

Alternatively, if you do not have the Linux kernel source code handy, you could perform the following steps:

* Comment out the following two lines in kvp_client.c
```C
#include <linux/connector.h>
#include "../include/linux/hyperv.h"
```

* Add the following definitions to kvp_client.c
```C
#define HV_KVP_EXCHANGE_MAX_KEY_SIZE     512
#define HV_KVP_EXCHANGE_MAX_VALUE_SIZE  2048
```

* Compile the kvp_client.c source file
```sh
gcc ./kvp_client.c -o ./kvp_client
```

**Note** that older Linux kernels limited the size of the buffers used by the KVP daemon, so the values of the above defines will need to be modified to:
```C
#define HV_KVP_EXCHANGE_MAX_KEY_SIZE     256
#define HV_KVP_EXCHANGE_MAX_VALUE_SIZE   512
```