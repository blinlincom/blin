<?php

use think\facade\Route;

Route::get('pay/payment_order', 'pay/payment_order');
Route::post('chat/webhook/:secret', 'wkim/webhook');
Route::post('chat/webhook', 'wkim/webhook');
Route::post('tron/addresses', 'tronwallet/addresses');
Route::post('tron/deposit', 'tronwallet/deposit');
Route::post('tron/task', 'tronwallet/task');
Route::post('tron/task_report', 'tronwallet/task_report');
Route::post('tron/confirm_task', 'tronwallet/confirm_task');
Route::post('tron/confirm_report', 'tronwallet/confirm_report');
Route::post('tron/gasfree_accounts', 'tronwallet/gasfree_accounts');
Route::post('tron/gasfree_sync', 'tronwallet/gasfree_sync');
Route::post('tron/gasfree_task', 'tronwallet/gasfree_task');
Route::post('tron/gasfree_report', 'tronwallet/gasfree_report');
Route::post('tron/gasfree_confirmations', 'tronwallet/gasfree_confirmations');
Route::post('tron/gasfree_confirm', 'tronwallet/gasfree_confirm');
