#import "ViewController.h"
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <sys/utsname.h>

@interface ViewController ()

@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIButton *runButton;

@property (nonatomic, assign) NSUInteger submittedFrames;
@property (nonatomic, assign) NSUInteger successfulCallbacks;
@property (nonatomic, assign) NSUInteger failedCallbacks;

@property (nonatomic, assign) BOOL running;

@end

static void OutputCallback(void *refCon,
                           void *sourceFrameRefCon,
                           OSStatus status,
                           VTEncodeInfoFlags flags,
                           CMSampleBufferRef sampleBuffer) {

    /*
     * Read callback arguments immediately.
     * Do not capture an unretained CMSampleBufferRef in an
     * asynchronous block.
     */
    BOOL hasSampleBuffer = (sampleBuffer != NULL);
    int callbackStatus = (int)status;
    unsigned int callbackFlags = (unsigned int)flags;

    ViewController *vc = (__bridge ViewController *)refCon;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (callbackStatus != noErr || !hasSampleBuffer) {
            vc.failedCallbacks++;

            [vc log:[NSString stringWithFormat:
                     @"Encoding callback: status=%d, flags=0x%x, sampleBuffer=%@",
                     callbackStatus,
                     callbackFlags,
                     hasSampleBuffer ? @"present" : @"NULL"]];
            return;
        }

        vc.successfulCallbacks++;

        [vc log:[NSString stringWithFormat:
                 @"Encoding callback #%lu: status=0, flags=0x%x",
                 (unsigned long)vc.successfulCallbacks,
                 callbackFlags]];
    });
}

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"AVE2Lab";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.runButton.translatesAutoresizingMaskIntoConstraints = NO;

    [self.runButton setTitle:@"Run VideoToolbox Diagnostics"
                    forState:UIControlStateNormal];

    self.runButton.titleLabel.font =
        [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];

    [self.runButton addTarget:self
                       action:@selector(runTest)
             forControlEvents:UIControlEventTouchUpInside];

    self.logView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.font =
        [UIFont monospacedSystemFontOfSize:12
                                   weight:UIFontWeightRegular];

    self.logView.backgroundColor = UIColor.secondarySystemBackgroundColor;

    [self.view addSubview:self.runButton];
    [self.view addSubview:self.logView];

    [NSLayoutConstraint activateConstraints:@[
        [self.runButton.topAnchor
         constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor
         constant:16],

        [self.runButton.leadingAnchor
         constraintEqualToAnchor:self.view.leadingAnchor
         constant:16],

        [self.runButton.trailingAnchor
         constraintEqualToAnchor:self.view.trailingAnchor
         constant:-16],

        [self.runButton.heightAnchor constraintEqualToConstant:48],

        [self.logView.topAnchor
         constraintEqualToAnchor:self.runButton.bottomAnchor
         constant:12],

        [self.logView.leadingAnchor
         constraintEqualToAnchor:self.view.leadingAnchor
         constant:12],

        [self.logView.trailingAnchor
         constraintEqualToAnchor:self.view.trailingAnchor
         constant:-12],

        [self.logView.bottomAnchor
         constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
         constant:-12]
    ]];

    struct utsname systemInfo;
    uname(&systemInfo);

    [self log:@"AVE2Lab diagnostic build"];
    [self log:[NSString stringWithFormat:
               @"OS: %@",
               NSProcessInfo.processInfo.operatingSystemVersionString]];

    [self log:[NSString stringWithFormat:
               @"Device identifier: %s",
               systemInfo.machine]];

    [self log:@"Test: ordinary H.264 encoding."];
    [self log:@"No deliberate vulnerability trigger is used."];
    [self log:@"Ready."];
}

- (void)log:(NSString *)message {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self log:message];
        });
        return;
    }

    NSString *text =
        [self.logView.text stringByAppendingFormat:@"%@\n", message];

    self.logView.text = text;

    [self.logView scrollRangeToVisible:
     NSMakeRange(text.length, 0)];

    NSLog(@"[AVE2Lab] %@", message);
}

- (void)runTest {
    if (self.running) {
        return;
    }

    self.running = YES;
    self.runButton.enabled = NO;

    self.submittedFrames = 0;
    self.successfulCallbacks = 0;
    self.failedCallbacks = 0;

    [self log:@"----------------------------------------"];
    [self log:@"Starting diagnostic run."];
    [self log:@"Codec: H.264"];
    [self log:@"Resolution: 640x480"];
    [self log:@"Frames requested: 60"];

    dispatch_async(
        dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [self performTest];
        });
}

- (void)performTest {
    const int width = 640;
    const int height = 480;
    const int count = 60;

    VTCompressionSessionRef session = NULL;

    OSStatus status = VTCompressionSessionCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCMVideoCodecType_H264,
        NULL,
        NULL,
        NULL,
        OutputCallback,
        (__bridge void *)self,
        &session
    );

    if (status != noErr || session == NULL) {
        [self finish:[NSString stringWithFormat:
                      @"Session creation failed: %d",
                      (int)status]];
        return;
    }

    [self log:[NSString stringWithFormat:
               @"Session creation status: %d",
               (int)status]];

    CFTypeRef hardwareValue = NULL;

    OSStatus hardwareStatus = VTSessionCopyProperty(
        session,
        kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
        kCFAllocatorDefault,
        &hardwareValue
    );

    if (hardwareStatus == noErr && hardwareValue != NULL) {
        if (CFGetTypeID(hardwareValue) == CFBooleanGetTypeID()) {
            BOOL enabled =
                CFBooleanGetValue((CFBooleanRef)hardwareValue);

            [self log:[NSString stringWithFormat:
                       @"Hardware encoder property: %@",
                       enabled ? @"true" : @"false"]];
        } else {
            [self log:[NSString stringWithFormat:
                       @"Hardware encoder property returned CF type ID: %lu",
                       (unsigned long)CFGetTypeID(hardwareValue)]];
        }

        CFRelease(hardwareValue);
    } else {
        [self log:[NSString stringWithFormat:
                   @"Hardware encoder property unavailable: %d",
                   (int)hardwareStatus]];

        if (hardwareValue != NULL) {
            CFRelease(hardwareValue);
        }
    }

    OSStatus realTimeStatus = VTSessionSetProperty(
        session,
        kVTCompressionPropertyKey_RealTime,
        kCFBooleanTrue
    );

    [self log:[NSString stringWithFormat:
               @"Set real-time property: %d",
               (int)realTimeStatus]];

    OSStatus profileStatus = VTSessionSetProperty(
        session,
        kVTCompressionPropertyKey_ProfileLevel,
        kVTProfileLevel_H264_Baseline_AutoLevel
    );

    [self log:[NSString stringWithFormat:
               @"Set H.264 profile property: %d",
               (int)profileStatus]];

    status = VTCompressionSessionPrepareToEncodeFrames(session);

    [self log:[NSString stringWithFormat:
               @"Prepare-to-encode status: %d",
               (int)status]];

    if (status != noErr) {
        VTCompressionSessionInvalidate(session);
        CFRelease(session);

        [self finish:[NSString stringWithFormat:
                      @"Preparation failed: %d",
                      (int)status]];
        return;
    }

    BOOL stoppedEarly = NO;

    for (int i = 0; i < count; i++) {
        CVPixelBufferRef pixel = NULL;

        NSDictionary *attributes = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey:
                @(kCVPixelFormatType_32BGRA),

            (NSString *)kCVPixelBufferWidthKey: @(width),
            (NSString *)kCVPixelBufferHeightKey: @(height),

            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
        };

        CVReturn pixelStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attributes,
            &pixel
        );

        if (pixelStatus != kCVReturnSuccess || pixel == NULL) {
            [self log:[NSString stringWithFormat:
                       @"Frame %d: pixel-buffer creation failed: %d",
                       i, (int)pixelStatus]];

            if (pixel != NULL) {
                CVPixelBufferRelease(pixel);
            }

            stoppedEarly = YES;
            break;
        }

        CVReturn lockStatus =
            CVPixelBufferLockBaseAddress(pixel, 0);

        if (lockStatus != kCVReturnSuccess) {
            [self log:[NSString stringWithFormat:
                       @"Frame %d: pixel-buffer lock failed: %d",
                       i, (int)lockStatus]];

            CVPixelBufferRelease(pixel);
            stoppedEarly = YES;
            break;
        }

        uint8_t *base = CVPixelBufferGetBaseAddress(pixel);
        size_t stride = CVPixelBufferGetBytesPerRow(pixel);

        for (int y = 0; y < height; y++) {
            uint8_t *row = base + (size_t)y * stride;

            for (int x = 0; x < width; x++) {
                size_t p = (size_t)x * 4;

                row[p] = (uint8_t)(x + i);
                row[p + 1] = (uint8_t)(y + i);
                row[p + 2] = (uint8_t)(x + y);
                row[p + 3] = 255;
            }
        }

        CVPixelBufferUnlockBaseAddress(pixel, 0);

        VTEncodeInfoFlags flags = 0;

        status = VTCompressionSessionEncodeFrame(
            session,
            pixel,
            CMTimeMake(i, 30),
            kCMTimeInvalid,
            NULL,
            NULL,
            &flags
        );

        CVPixelBufferRelease(pixel);

        if (status != noErr) {
            [self log:[NSString stringWithFormat:
                       @"Frame %d submission failed: %d",
                       i, (int)status]];

            stoppedEarly = YES;
            break;
        }

        self.submittedFrames++;
    }

    OSStatus completionStatus =
        VTCompressionSessionCompleteFrames(session, kCMTimeInvalid);

    [self log:[NSString stringWithFormat:
               @"Complete-frames status: %d",
               (int)completionStatus]];

    VTCompressionSessionInvalidate(session);
    CFRelease(session);

    NSString *result = [NSString stringWithFormat:
                        @"Run finished. Frames submitted: %lu/%d. Early stop: %@.",
                        (unsigned long)self.submittedFrames,
                        count,
                        stoppedEarly ? @"yes" : @"no"];

    [self finish:result];
}

- (void)finish:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self log:message];

        [self log:[NSString stringWithFormat:
                   @"Successful output callbacks: %lu",
                   (unsigned long)self.successfulCallbacks]];

        [self log:[NSString stringWithFormat:
                   @"Failed output callbacks: %lu",
                   (unsigned long)self.failedCallbacks]];

        [self log:@"Diagnostic run complete."];

        self.running = NO;
        self.runButton.enabled = YES;
    });
}

@end
