idf_component_register(
  SRCS "${CMAKE_CURRENT_LIST_DIR}/../../idf/main.c"
       "${CMAKE_CURRENT_LIST_DIR}/../../idf/vos_hal.c"
  INCLUDE_DIRS "${CMAKE_CURRENT_LIST_DIR}/../../idf"
  REQUIRES vos esp_timer nvs_flash driver)
target_compile_definitions(${COMPONENT_LIB} PRIVATE "VOS_TAG=\"c3\"")
