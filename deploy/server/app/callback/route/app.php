<?php

use think\facade\Route;

Route::get('pay/payment_order', 'pay/payment_order');
Route::post('chat/webhook/:secret', 'wkim/webhook');
Route::post('chat/webhook', 'wkim/webhook');
Route::post('tron/addresses', 'tronwallet/addresses');
Route::post('tron/deposit', 'tronwallet/deposit');
