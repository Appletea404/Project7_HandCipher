# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "/home/kwakyj91/workspace_ondevice_2/project/project_07/Project7_HandCipher/Vitis/platform_HandCipher/microblaze_riscv_0/standalone_microblaze_riscv_0/bsp/include/sleep.h"
  "/home/kwakyj91/workspace_ondevice_2/project/project_07/Project7_HandCipher/Vitis/platform_HandCipher/microblaze_riscv_0/standalone_microblaze_riscv_0/bsp/include/xiltimer.h"
  "/home/kwakyj91/workspace_ondevice_2/project/project_07/Project7_HandCipher/Vitis/platform_HandCipher/microblaze_riscv_0/standalone_microblaze_riscv_0/bsp/include/xtimer_config.h"
  "/home/kwakyj91/workspace_ondevice_2/project/project_07/Project7_HandCipher/Vitis/platform_HandCipher/microblaze_riscv_0/standalone_microblaze_riscv_0/bsp/lib/libxiltimer.a"
  )
endif()
