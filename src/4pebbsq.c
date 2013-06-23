#include "pebble_os.h"
#include "pebble_app.h"
#include "pebble_fonts.h"
#include "mini-print.h"

#define MY_UUID { 0x4E, 0x1A, 0x5A, 0x91, 0x9E, 0xB0, 0x45, 0x2A, 0xB7, 0x52, 0xD4, 0x42, 0x64, 0xB1, 0x89, 0xB6 }
PBL_APP_INFO(MY_UUID,
						 "4pebbsq", "Pebbru",
						 0, 1,
						 DEFAULT_MENU_ICON,
						 APP_INFO_STANDARD_APP);

typedef struct {
	char* id;
	char* name;
	char* distance;
	char* people_here;
} FsqVenue;

typedef struct {
	MenuLayer layer;
	FsqVenue venues[25];
	char menu_entries[25][25];
} MenuLib;

static MenuLib menu_stack[1];

Window window;
int current_id = 0;

void menu_item_selected_callback(struct MenuLayer *menu_layer, MenuIndex *cell_index, void *context);
void add_menu_item(int id, char *title, char *subtitle, char *fsqid);
void receive(DictionaryIterator *received, void *context);
void send_message(char *action, char *params);

void menu_item_selected_callback(struct MenuLayer *menu_layer, MenuIndex *cell_index, void *context) {
	MenuLib *menu = (MenuLib*)context;
	send_message("checkin", menu->venues[cell_index->row].id);
}
uint16_t mainMenu_get_num_rows_in_section(struct MenuLayer *menu_layer, uint16_t section_index, void *callback_context) {
	return current_id;
}
uint16_t mainMenu_get_num_sections(struct MenuLayer *menu_layer, void *callback_context) {
	return 1;
}
void mainMenu_draw_row(GContext *ctx, const Layer *cell_layer, MenuIndex *cell_index, void *callback_context) {
	MenuLib *menu = (MenuLib*)callback_context;
	menu_cell_basic_draw(ctx, cell_layer, menu->venues[cell_index->row].name, menu->venues[cell_index->row].id, NULL);
}
void mainMenu_draw_header(GContext *ctx, const Layer *cell_layer, uint16_t section_index, void *callback_context) {
	menu_cell_basic_header_draw(ctx, cell_layer, "4pebbsq");
}

void send_message(char *action, char *params) {
	DictionaryIterator *iter;
	app_message_out_get(&iter);
	dict_write_cstring(iter, 0, action);
	dict_write_cstring(iter, 1, params);
	dict_write_end(iter);
	app_message_out_send();
	app_message_out_release();
}

void receive(DictionaryIterator *received, void *context) {
	char* action = dict_find(received, 0)->value->cstring;
	MenuLib *menu = &menu_stack[0];
	if (strcmp(action, (char*)"add_venue") == 0) {
		memset(menu->venues[current_id].id, 0, 25);
		memset(menu->venues[current_id].name, 0, 25);
		memset(menu->venues[current_id].distance, 0, 25);
		memset(menu->venues[current_id].people_here, 0, 25);
		memcpy(menu->venues[current_id].id, &dict_find(received, 1)->value->cstring, 24);
		memcpy(menu->venues[current_id].name, &dict_find(received, 2)->value->cstring, 24);
		memcpy(menu->venues[current_id].distance, &dict_find(received, 3)->value->cstring, 24);
		memcpy(menu->venues[current_id].people_here, &dict_find(received, 4)->value->cstring, 24);
		send_message("fur realz", menu->venues[current_id].id);
		current_id ++;
	}
	else if (strcmp(action, (char*)"completed_venues") == 0) {
		send_message("fur lulz", menu->venues[0].id);
		menu_layer_reload_data(&menu->layer);
	}
}

MenuLayerCallbacks cbacks;

void handle_init(AppContextRef ctx) {
	(void)ctx;

	window_init(&window, "Window");
	MenuLib *menu = &menu_stack[0];
	menu_layer_init(&menu->layer, GRect(0,0,window.layer.frame.size.w,window.layer.frame.size.h-15));
	menu_layer_set_click_config_onto_window(&menu->layer, &window);
	cbacks.get_num_sections = &mainMenu_get_num_sections;;
	cbacks.get_num_rows = &mainMenu_get_num_rows_in_section;
	cbacks.select_click = &menu_item_selected_callback;
	cbacks.draw_row = &mainMenu_draw_row;
	cbacks.draw_header = &mainMenu_draw_header;
	menu_layer_set_callbacks(&menu->layer, NULL, cbacks);
	layer_add_child(&window.layer, menu_layer_get_layer(&menu->layer));
	window_stack_push(&window, true);
	send_message("get_locations", "");
}


void pbl_main(void *params) {
	PebbleAppHandlers handlers = {
		.init_handler = &handle_init,
		.messaging_info = {
			.buffer_sizes = {
				.inbound = 512,
				.outbound = 512,
			},
			.default_callbacks.callbacks = {
				.in_received = receive,
			},
		},
	};
	app_event_loop(params, &handlers);
}
