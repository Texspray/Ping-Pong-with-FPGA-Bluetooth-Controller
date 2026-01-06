/*
   Código de Resolução Final para ESP32 - Servidor BLE (Controle de GPIOs)

   Estratégia: Força o anúncio do Service UUID no pacote principal de advertising,
   removendo o nome do dispositivo para garantir que o pacote não exceda o limite de 31 bytes.
   Isto maximiza a probabilidade de descoberta por aplicações web.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "esp_system.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "esp_bt.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_main.h"
#include "esp_gatt_common_api.h"
#include "driver/gpio.h"

#define GATTS_TAG "GPIO_SERVER"

// --- Definições do Hardware e Serviço ---
#define GPIO_OUT_1_ACTIVELOW    GPIO_NUM_5
#define GPIO_OUT_2_ACTIVELOW    GPIO_NUM_4
#define DEVICE_NAME             "Controle1"
#define SERVICE_UUID            0x00FF
#define CHARACTERISTIC_UUID     0xFF01

#define PROFILE_APP_ID 0

struct gatts_profile_inst {
    esp_gatts_cb_t gatts_cb;
    uint16_t gatts_if;
    uint16_t app_id;
    uint16_t conn_id;
    uint16_t service_handle;
    esp_gatt_srvc_id_t service_id;
    uint16_t char_handle;
    esp_bt_uuid_t char_uuid;
};

static void gatts_profile_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param);

static struct gatts_profile_inst app_profile = {
    .gatts_cb = gatts_profile_event_handler,
    .gatts_if = ESP_GATT_IF_NONE,
};

// --- ALTERAÇÃO ESTRATÉGICA ---
// Anuncia o UUID do serviço no pacote principal e omite o nome.
static uint16_t service_uuid_list[] = {SERVICE_UUID};
static esp_ble_adv_data_t adv_data = {
    .set_scan_rsp = false,
    .include_name = false, // Nome removido para garantir espaço
    .include_txpower = true,
    .service_uuid_len = sizeof(service_uuid_list),
    .p_service_uuid = (uint8_t*)service_uuid_list,
    .flag = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
};


static esp_ble_adv_params_t adv_params = {
    .adv_int_min       = 0x20,
    .adv_int_max       = 0x40,
    .adv_type          = ADV_TYPE_IND,
    .own_addr_type     = BLE_ADDR_TYPE_PUBLIC,
    .channel_map       = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

static void configure_gpios(void) {
    ESP_LOGI(GATTS_TAG, "Configurando GPIOs (ambos Active-Low)...");
    gpio_config_t io_conf = {};
    io_conf.intr_type = GPIO_INTR_DISABLE;
    io_conf.mode = GPIO_MODE_OUTPUT;
    io_conf.pin_bit_mask = (1ULL << GPIO_OUT_1_ACTIVELOW) | (1ULL << GPIO_OUT_2_ACTIVELOW);
    io_conf.pull_down_en = 0;
    io_conf.pull_up_en = 0;
    gpio_config(&io_conf);
    gpio_set_level(GPIO_OUT_1_ACTIVELOW, 1);
    gpio_set_level(GPIO_OUT_2_ACTIVELOW, 1);
}

static void gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param) {
    switch (event) {
        case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
            if (param->adv_start_cmpl.status == ESP_BT_STATUS_SUCCESS) {
                ESP_LOGI(GATTS_TAG, "Advertising iniciado com sucesso.");
            } else {
                ESP_LOGE(GATTS_TAG, "Falha ao iniciar advertising, código de erro: %d", param->adv_start_cmpl.status);
            }
            break;
        default:
            break;
    }
}

static void gatts_profile_event_handler(esp_gatts_cb_event_t event, esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param) {
    switch (event) {
        case ESP_GATTS_REG_EVT:
            esp_ble_gap_set_device_name(DEVICE_NAME);
            esp_ble_gap_config_adv_data(&adv_data);
            
            app_profile.service_id.is_primary = true;
            app_profile.service_id.id.inst_id = 0x00;
            app_profile.service_id.id.uuid.len = ESP_UUID_LEN_16;
            app_profile.service_id.id.uuid.uuid.uuid16 = SERVICE_UUID;
            esp_ble_gatts_create_service(gatts_if, &app_profile.service_id, 4);
            break;
        case ESP_GATTS_CREATE_EVT:
            app_profile.service_handle = param->create.service_handle;
            esp_ble_gatts_start_service(app_profile.service_handle);
            app_profile.char_uuid.len = ESP_UUID_LEN_16;
            app_profile.char_uuid.uuid.uuid16 = CHARACTERISTIC_UUID;
            esp_ble_gatts_add_char(app_profile.service_handle, &app_profile.char_uuid,
                                   ESP_GATT_PERM_WRITE, ESP_GATT_CHAR_PROP_BIT_WRITE_NR, NULL, NULL);
            break;
        case ESP_GATTS_ADD_CHAR_EVT:
            app_profile.char_handle = param->add_char.attr_handle;
            esp_ble_gap_start_advertising(&adv_params);
            break;
        case ESP_GATTS_CONNECT_EVT:
            ESP_LOGI(GATTS_TAG, "Cliente conectado, conn_id %" PRIu16, param->connect.conn_id);
            app_profile.conn_id = param->connect.conn_id;
            break;
        case ESP_GATTS_DISCONNECT_EVT:
            ESP_LOGI(GATTS_TAG, "Cliente desconectado, motivo 0x%x", param->disconnect.reason);
            gpio_set_level(GPIO_OUT_1_ACTIVELOW, 1);
            gpio_set_level(GPIO_OUT_2_ACTIVELOW, 1);
            esp_ble_gap_start_advertising(&adv_params);
            break;
        case ESP_GATTS_WRITE_EVT:
            if (param->write.handle == app_profile.char_handle && param->write.len > 0) {
                char command = param->write.value[0];
                switch(command) {
                    case '1': gpio_set_level(GPIO_OUT_1_ACTIVELOW, 0); break;
                    case '0': gpio_set_level(GPIO_OUT_1_ACTIVELOW, 1); break;
                    case '2': gpio_set_level(GPIO_OUT_2_ACTIVELOW, 0); break;
                    case '3': gpio_set_level(GPIO_OUT_2_ACTIVELOW, 1); break;
                }
            }
            break;
        default:
            break;
    }
}

void app_main(void) {
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
    configure_gpios();
    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));
    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_bt_controller_init(&bt_cfg));
    ESP_ERROR_CHECK(esp_bt_controller_enable(ESP_BT_MODE_BLE));
    ESP_ERROR_CHECK(esp_bluedroid_init());
    ESP_ERROR_CHECK(esp_bluedroid_enable());
    ESP_ERROR_CHECK(esp_ble_gatts_register_callback(gatts_profile_event_handler));
    ESP_ERROR_CHECK(esp_ble_gap_register_callback(gap_event_handler));
    ESP_ERROR_CHECK(esp_ble_gatts_app_register(PROFILE_APP_ID));
    ESP_LOGI(GATTS_TAG, "Inicialização completa. Pronto para receber conexões.");
}
