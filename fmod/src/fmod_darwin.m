#include "fmod_ext.h"
#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE

#import <AVFoundation/AVFoundation.h>
#include <string.h>

#define AUDIO_RESUME_RETRY_COUNT 20
#define AUDIO_RESUME_RETRY_INTERVAL 0.2

static NSTimer* resumeTimer = nil;

void FMODExt_logIOSAudioSession(const char* phase) {
    @autoreleasepool {
        AVAudioSession* session = [AVAudioSession sharedInstance];
        LOGI("iOS audio session %s: category=%s options=%lu secondary_audio=%d", phase,
             [[session category] UTF8String], (unsigned long)[session categoryOptions],
             (int)[session secondaryAudioShouldBeSilencedHint]);
    }
}

bool FMODExt_configureIOSAudioSession() {
    @autoreleasepool {
        const char* policy = FMODExt_dmConfigFile_GetString("fmod.audio_session_category", "default");
        if (strcmp(policy, "default") == 0) { return true; }
        if (strcmp(policy, "ambient") != 0) {
            LOGE("Invalid fmod.audio_session_category: %s (expected default or ambient)", policy);
            return false;
        }

        // Configure mixing before FMOD opens output. Do not activate the session here.
        NSError* error = nil;
        BOOL success = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient
                                                      withOptions:0 error:&error];
        if (!success) {
            LOGE("Cannot configure Ambient audio session: %s",
                 error ? [[error localizedDescription] UTF8String] : "no error was issued");
        }
        return success;
    }
}

// In case it doesn't work from the first try, retry activating the audio session
// a few times. For example, after dismissing a phone call, [AVAudioSession setActive: error:]
// errors out from the first try, but works on the second
static void resumeAudioSession(int retries) {
    @autoreleasepool {
        if (FMODExt_configureIOSAudioSession()) {
            NSError* error = nil;
            BOOL success = [[AVAudioSession sharedInstance] setActive:TRUE error:&error];
            if (success) {
                FMODExt_resumeMixer();
                return;
            }

            if (error) {
                LOGW("Cannot activate audio session: %s", [[error localizedDescription] UTF8String]);
            } else {
                LOGW("Cannot activate audio session and no error was issued");
            }
        }

        if (retries <= 0) {
            LOGE("Cannot restore audio session. Not retrying anymore.");
            return;
        }

        resumeTimer = [NSTimer scheduledTimerWithTimeInterval:AUDIO_RESUME_RETRY_INTERVAL
                                                      repeats:NO
                                                        block:^(NSTimer* timer) {
                                                          resumeTimer = nil;
                                                          resumeAudioSession(retries - 1);
                                                        }];
    }
}

void FMODExt_initIOSInterruptionHandler() {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter]
            addObserverForName:AVAudioSessionInterruptionNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification* notification) {
                      NSUInteger typeValue =
                          [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] intValue];

                      if (typeValue == AVAudioSessionInterruptionTypeBegan) {
                          if (resumeTimer) {
                              [resumeTimer invalidate];
                              resumeTimer = nil;
                          }
                          FMODExt_suspendMixer();

                      } else if (typeValue == AVAudioSessionInterruptionTypeEnded) {
                          NSUInteger optionsValue =
                              [[notification.userInfo valueForKey:AVAudioSessionInterruptionOptionKey] intValue];
                          if (optionsValue & AVAudioSessionInterruptionOptionShouldResume) {
                              resumeAudioSession(AUDIO_RESUME_RETRY_COUNT);
                          }
                      }
                    }];
    }
}
#endif

int FMODExt_getBundleRoot(lua_State* L) {
    @autoreleasepool {
        NSString* path = [[NSBundle mainBundle] bundlePath];
        lua_pushstring(L, [path UTF8String]);
    }
    return 1;
}
