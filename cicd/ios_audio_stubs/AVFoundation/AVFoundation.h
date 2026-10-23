// Minimal AVAudioSession double for host tests of the actual iOS implementation.
#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, AVAudioSessionCategoryOptions) { TestCategoryOptionsNone = 0 };
static NSString* const AVAudioSessionCategoryAmbient = @"AVAudioSessionCategoryAmbient";
static NSString* const AVAudioSessionInterruptionNotification = @"TestAudioInterruption";
static NSString* const AVAudioSessionInterruptionTypeKey = @"type";
static NSString* const AVAudioSessionInterruptionOptionKey = @"options";
enum { AVAudioSessionInterruptionTypeBegan = 1, AVAudioSessionInterruptionTypeEnded = 0,
       AVAudioSessionInterruptionOptionShouldResume = 1 };

@interface AVAudioSession : NSObject
+ (instancetype)sharedInstance;
- (BOOL)setCategory:(NSString*)category withOptions:(AVAudioSessionCategoryOptions)options error:(NSError**)error;
- (BOOL)setActive:(BOOL)active error:(NSError**)error;
- (NSString*)category;
- (AVAudioSessionCategoryOptions)categoryOptions;
- (BOOL)secondaryAudioShouldBeSilencedHint;
@end
