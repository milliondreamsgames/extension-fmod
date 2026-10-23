// Compile the production C/Objective-C paths against deterministic session/FMOD doubles.
// This verifies control flow, not physical-device audio coexistence.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#include <assert.h>
#include <string.h>
#undef TARGET_OS_IPHONE
#define TARGET_OS_IPHONE 1
#include "../fmod/src/fmod_ext.h"
// Avoid colliding with Apple's class if Foundation loads the real AudioSession framework.
#define AVAudioSession TestAudioSession
#import <AVFoundation/AVFoundation.h>

static const char* policy = "ambient";
static int categories, activations, links, creates, initializes, registrations, resumes, timers, releases;
static bool failCategory, failActivation, failInitialize;
static NSString* currentCategory = @"SoloAmbient";
static AVAudioSessionCategoryOptions currentOptions = 0;

@implementation AVAudioSession
+ (instancetype)sharedInstance {
    static AVAudioSession* session;
    if (!session) { session = [AVAudioSession new]; }
    return session;
}
- (BOOL)setCategory:(NSString*)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError**)error {
    categories++;
    assert(error && *error == nil);
    assert([category isEqualToString:AVAudioSessionCategoryAmbient]);
    assert(options == 0); // No ducking or spoken-audio interruption options.
    if (failCategory) { return NO; } // Also exercise failure with no NSError.
    currentCategory = category;
    currentOptions = options;
    return YES;
}
- (BOOL)setActive:(BOOL)active error:(NSError**)error {
    activations++;
    assert(active && error && *error == nil);
    if (strcmp(policy, "ambient") == 0 && !failCategory) {
        assert([currentCategory isEqualToString:AVAudioSessionCategoryAmbient]);
    }
    if (failActivation) {
        *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
        return NO;
    }
    return YES;
}
- (NSString*)category { return currentCategory; }
- (AVAudioSessionCategoryOptions)categoryOptions { return currentOptions; }
- (BOOL)secondaryAudioShouldBeSilencedHint { return YES; }
@end

@interface TestTimer : NSObject
@property(copy) void (^callback)(TestTimer*);
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats
                                        block:(void (^)(TestTimer*))block;
- (void)invalidate;
@end
static TestTimer* pendingTimer;
@implementation TestTimer
+ (instancetype)scheduledTimerWithTimeInterval:(NSTimeInterval)interval repeats:(BOOL)repeats
                                        block:(void (^)(TestTimer*))block {
    assert(interval == 0.2 && !repeats);
    timers++;
    pendingTimer = [TestTimer new];
    pendingTimer.callback = block;
    return pendingTimer;
}
- (void)invalidate { self.callback = nil; pendingTimer = nil; }
@end

#define NSTimer TestTimer
#include "../fmod/src/fmod_darwin.m"
#undef NSTimer
#include "../fmod/src/fmod_init.c"

const char* FMODExt_dmConfigFile_GetString(const char* key, const char* fallback) {
    return strcmp(key, "fmod.audio_session_category") == 0 ? policy : fallback;
}
int32_t FMODExt_dmConfigFile_GetInt(const char* key, int32_t fallback) { return fallback; }
bool FMODExt_linkLibraries() { links++; return true; }
void FMODExt_cleanupLibraries() {}
void FMODExt_register(lua_State* L) { registrations++; }
FMOD_RESULT FMOD_Studio_System_Create(FMOD_STUDIO_SYSTEM** system, unsigned int version) {
    creates++;
    if (strcmp(policy, "ambient") == 0) {
        assert(categories == 1); // Attempt the policy before creating FMOD, even if it fails.
        assert([currentCategory isEqualToString:failCategory ? @"SoloAmbient" : AVAudioSessionCategoryAmbient]);
    }
    *system = (FMOD_STUDIO_SYSTEM*)(uintptr_t)1;
    return FMOD_OK;
}
FMOD_RESULT FMOD_Studio_System_GetCoreSystem(FMOD_STUDIO_SYSTEM* system, FMOD_SYSTEM** core) {
    *core = (FMOD_SYSTEM*)(uintptr_t)2;
    return FMOD_OK;
}
FMOD_RESULT FMOD_System_SetDSPBufferSize(FMOD_SYSTEM* s, unsigned int length, int count) { return FMOD_OK; }
FMOD_RESULT FMOD_System_SetSoftwareFormat(FMOD_SYSTEM* s, int rate, FMOD_SPEAKERMODE mode, int speakers) { return FMOD_OK; }
FMOD_RESULT FMOD_Studio_System_Initialize(FMOD_STUDIO_SYSTEM* s, int channels, FMOD_STUDIO_INITFLAGS studio,
                                       FMOD_INITFLAGS flags, void* data) {
    initializes++;
    assert(activations == 0); // Startup must let FMOD own activation.
    return failInitialize ? FMOD_ERR_OUTPUT_INIT : FMOD_OK;
}
FMOD_RESULT FMOD_Studio_System_Release(FMOD_STUDIO_SYSTEM* s) { releases++; return FMOD_OK; }
FMOD_RESULT FMOD_System_MixerSuspend(FMOD_SYSTEM* s) { return FMOD_OK; }
FMOD_RESULT FMOD_System_MixerResume(FMOD_SYSTEM* s) {
    resumes++;
    assert(!failActivation && activations > 0);
    return FMOD_OK;
}

static void interruption(NSUInteger type, NSUInteger options) {
    [[NSNotificationCenter defaultCenter] postNotificationName:AVAudioSessionInterruptionNotification
        object:nil userInfo:@{ AVAudioSessionInterruptionTypeKey: @(type),
                              AVAudioSessionInterruptionOptionKey: @(options) }];
}
static void fireTimer() {
    TestTimer* timer = pendingTimer;
    pendingTimer = nil;
    assert(timer.callback);
    timer.callback(timer);
}

int main(int argc, const char** argv) {
    @autoreleasepool {
        assert(argc == 2);
        const char* scenario = argv[1];
        if (strcmp(scenario, "default") == 0 || strcmp(scenario, "resume-default") == 0) { policy = "default"; }
        if (strcmp(scenario, "invalid") == 0) { policy = "ambinet"; }
        failCategory = strcmp(scenario, "startup-failure") == 0 ||
                       strcmp(scenario, "startup-category-fmod-failure") == 0;
        failInitialize = strcmp(scenario, "startup-fmod-failure") == 0 ||
                         strcmp(scenario, "startup-category-fmod-failure") == 0;
        FMODExt_init(NULL);
        if (failInitialize) {
            assert(links == 1 && creates == 1 && initializes == 1 && registrations == 0);
            assert(releases == 1 && FMODExt_system == NULL && activations == 0);
            return 0;
        }
        assert(releases == 0 && FMODExt_system != NULL);
        if (failCategory || strcmp(scenario, "invalid") == 0) {
            assert([currentCategory isEqualToString:@"SoloAmbient"]);
        }
        assert(links == 1 && creates == 1 && initializes == 1 && registrations == 1);
        assert(categories == (strcmp(policy, "ambient") == 0 ? 1 : 0));
        assert(activations == 0);
        if (strncmp(scenario, "resume-", 7) != 0) { return 0; }

        interruption(AVAudioSessionInterruptionTypeBegan, 0);
        assert(FMODExt_isPaused);
        // Simulate another writer resetting the category during the interruption.
        currentCategory = @"SoloAmbient";
        failCategory = strcmp(scenario, "resume-category-failure") == 0 ||
                       strcmp(scenario, "resume-category-activation-failure") == 0 ||
                       strcmp(scenario, "resume-category-retry-success") == 0;
        failActivation = strcmp(scenario, "resume-activation-failure") == 0 ||
                         strcmp(scenario, "resume-category-activation-failure") == 0 ||
                         strcmp(scenario, "resume-retry-success") == 0 ||
                         strcmp(scenario, "resume-category-retry-success") == 0 ||
                         strcmp(scenario, "resume-cancel-retry") == 0;
        bool noResume = strcmp(scenario, "resume-not-permitted") == 0;
        interruption(AVAudioSessionInterruptionTypeEnded,
                     noResume ? 0 : AVAudioSessionInterruptionOptionShouldResume);
        if (noResume) {
            assert(categories == 1 && activations == 0 && resumes == 0 && timers == 0);
        } else if (strcmp(scenario, "resume-cancel-retry") == 0) {
            assert(pendingTimer && resumes == 0);
            interruption(AVAudioSessionInterruptionTypeBegan, 0);
            assert(!pendingTimer && resumes == 0 && FMODExt_isPaused);
        } else if (strcmp(scenario, "resume-retry-success") == 0 ||
                   strcmp(scenario, "resume-category-retry-success") == 0) {
            assert(pendingTimer && resumes == 0);
            failActivation = false;
            fireTimer();
            assert(resumes == 1 && !FMODExt_isPaused && !pendingTimer);
            assert(categories == 3 && activations == 2 && timers == 1);
        } else if (failActivation) {
            while (pendingTimer) { fireTimer(); }
            assert(timers == AUDIO_RESUME_RETRY_COUNT);
            assert(categories == 2 + AUDIO_RESUME_RETRY_COUNT);
            assert(activations == 1 + AUDIO_RESUME_RETRY_COUNT);
            assert(resumes == 0 && FMODExt_isPaused);
        } else if (strcmp(scenario, "resume-default") == 0) {
            assert(categories == 0 && activations == 1 && resumes == 1 && !FMODExt_isPaused);
            assert([currentCategory isEqualToString:@"SoloAmbient"]);
        } else {
            assert(categories == 2 && activations == 1 && resumes == 1 && !FMODExt_isPaused);
            assert(timers == 0);
        }
        if (failCategory) { assert([currentCategory isEqualToString:@"SoloAmbient"]); }
    }
    return 0;
}
