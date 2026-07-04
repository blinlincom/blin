//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<mmkv_ios/MMKVPlugin.h>)
#import <mmkv_ios/MMKVPlugin.h>
#else
@import mmkv_ios;
#endif

#if __has_include(<photo_manager/PhotoManagerPlugin.h>)
#import <photo_manager/PhotoManagerPlugin.h>
#else
@import photo_manager;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [MMKVPlugin registerWithRegistrar:[registry registrarForPlugin:@"MMKVPlugin"]];
  [PhotoManagerPlugin registerWithRegistrar:[registry registrarForPlugin:@"PhotoManagerPlugin"]];
}

@end
