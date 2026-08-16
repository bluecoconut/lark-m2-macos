#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>
#import "hidapi.h"

static const unsigned short kLarkVendorID = 0x3547;
static const unsigned short kLarkProductID = 0x0007;
static const unsigned char kStandardReportID = 0x55;
static const unsigned char kProductReportID = 0x05;
static NSString * const kAudioModeDefaultsKey = @"LarkAudioMode";

static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = NSColor.labelColor; label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}
static NSStackView *InfoRow(NSString *name, NSView *value) {
    NSTextField *nameLabel = Label(name, 12, NSFontWeightRegular); nameLabel.textColor = NSColor.secondaryLabelColor;
    NSView *spacer = [[NSView alloc] init]; spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *row = [NSStackView stackViewWithViews:@[nameLabel, spacer, value]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal; row.alignment = NSLayoutAttributeCenterY; row.spacing = 8; row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:24].active = YES; return row;
}
static NSPopUpButton *Popup(NSArray<NSString *> *items, SEL action, id target, CGFloat width) {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [popup addItemsWithTitles:items]; popup.controlSize = NSControlSizeSmall;
    popup.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    popup.target = target; popup.action = action; popup.translatesAutoresizingMaskIntoConstraints = NO;
    [popup.widthAnchor constraintEqualToConstant:width].active = YES;
    return popup;
}

static void BuildRequest(unsigned char packet[64], unsigned char reportID,
                         unsigned char command, unsigned char device,
                         const unsigned char *payload, unsigned short length) {
    memset(packet, 0, 64); packet[0] = reportID; packet[1] = 0xAA; packet[2] = 0xDD;
    packet[3] = command; packet[4] = device; packet[5] = (unsigned char)(length >> 8);
    packet[6] = (unsigned char)length; if (length) memcpy(packet + 7, payload, length);
    for (unsigned int index = 1; index <= 6U + length; ++index) packet[7 + length] ^= packet[index];
}
static void BuildProductRequest(unsigned char packet[64], unsigned char command,
                                const unsigned char *payload, unsigned short length) {
    memset(packet, 0, 64); packet[0] = kProductReportID; packet[1] = 0xAA; packet[2] = 0xDD;
    packet[3] = command; packet[4] = (unsigned char)(length >> 8); packet[5] = (unsigned char)length;
    if (length) memcpy(packet + 6, payload, length);
    for (unsigned int index = 1; index <= 5U + length; ++index) packet[6 + length] ^= packet[index];
}
static BOOL ProductExchange(hid_device *hid, unsigned char request[64], unsigned char command,
                            unsigned char *payload, int *payloadLength) {
    unsigned char stale[128]; while (hid_read_timeout(hid, stale, sizeof(stale), 0) > 0) {}
    if (hid_write(hid, request, 64) != 64) return NO;
    unsigned char response[128] = {0}; int count = hid_read_timeout(hid, response, sizeof(response), 800);
    int offset = count > 0 && response[0] == kProductReportID ? 1 : 0;
    if (count < offset + 6 || response[offset] != 0xBB || response[offset + 1] != 0xDD || response[offset + 2] != command) return NO;
    int length = response[offset + 3] * 256 + response[offset + 4];
    if (length < 0 || offset + 6 + length > count) return NO;
    unsigned char checksum = 0;
    for (int index = offset; index < offset + 5 + length; ++index) checksum ^= response[index];
    if (checksum != response[offset + 5 + length]) return NO;
    if (payload && length) memcpy(payload, response + offset + 5, (size_t)length);
    if (payloadLength) *payloadLength = length; return YES;
}

@interface MicStatusView : NSStackView
@property NSTextField *state;
@property NSView *battery;
- (void)setConnected:(BOOL)connected battery:(NSInteger)battery;
@end

@interface BatteryBadgeView : NSView
@property (nonatomic) NSInteger percentage;
@end

@implementation BatteryBadgeView
- (void)setPercentage:(NSInteger)percentage {
    _percentage = percentage;
    [self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect body = NSMakeRect(0.5, 1.25, NSWidth(self.bounds) - 4.0, NSHeight(self.bounds) - 2.5);
    NSRect cap = NSMakeRect(NSMaxX(body) + 0.8, NSMidY(body) - 3.1, 2.1, 6.2);
    NSColor *color = self.percentage <= 15 ? NSColor.systemRedColor : NSColor.systemGreenColor;
    [color setStroke];
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:body xRadius:3.0 yRadius:3.0]; outline.lineWidth = 1.15; [outline stroke];
    [[NSBezierPath bezierPathWithRoundedRect:cap xRadius:0.8 yRadius:0.8] fill];
    CGFloat fillWidth = MAX(2.0, (NSWidth(body) - 3.0) * MIN(1.0, MAX(0.0, self.percentage / 100.0)));
    [[color colorWithAlphaComponent:0.24] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(body.origin.x + 1.5, body.origin.y + 1.5, fillWidth, NSHeight(body) - 3.0) xRadius:1.6 yRadius:1.6] fill];
    NSString *text = [NSString stringWithFormat:@"%ld%%", (long)self.percentage];
    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:9.5 weight:NSFontWeightSemibold], NSForegroundColorAttributeName: NSColor.labelColor };
    NSSize size = [text sizeWithAttributes:attributes];
    [text drawAtPoint:NSMakePoint(NSMidX(body) - size.width / 2.0, NSMidY(body) - size.height / 2.0 - 0.4) withAttributes:attributes];
}
@end

@implementation MicStatusView
- (instancetype)init {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.alignment = NSLayoutAttributeCenterY;
    self.spacing = 4;
    self.state = Label(@"—", 12, NSFontWeightSemibold);
    self.battery = [[BatteryBadgeView alloc] initWithFrame:NSZeroRect];
    self.battery.translatesAutoresizingMaskIntoConstraints = NO;
    [self.battery.widthAnchor constraintEqualToConstant:34].active = YES;
    [self.battery.heightAnchor constraintEqualToConstant:14].active = YES;
    [self addArrangedSubview:self.state]; [self addArrangedSubview:self.battery];
    return self;
}
- (void)setConnected:(BOOL)connected battery:(NSInteger)batteryLevel {
    if (!connected) {
        self.state.stringValue = @"Not connected";
        self.state.textColor = NSColor.systemRedColor;
        self.battery.hidden = YES;
        return;
    }
    self.state.stringValue = @"Connected";
    self.state.textColor = NSColor.systemGreenColor;
    self.battery.hidden = NO;
    ((BatteryBadgeView *)self.battery).percentage = batteryLevel;
}
@end
static NSImage *LarkIcon(void) {
    NSImageSymbolConfiguration *configuration = [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular];
    NSImage *image = [NSImage imageWithSystemSymbolName:@"antenna.radiowaves.left.and.right" accessibilityDescription:@"Lark M2 status"];
    image = [image imageWithSymbolConfiguration:configuration];
    image.template = YES;
    return image;
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property hid_device *hid;
@property dispatch_queue_t hidQueue;
@property BOOL pollInFlight, controlInFlight, receiverPresent, tx1Connected, tx2Connected, audioModeApplied;
@property NSInteger tx1Battery, tx2Battery, gain, noise, desiredAudioMode;
@property NSTimer *timer;
@property NSStatusItem *statusItem;
@property NSMenu *menu;
@property NSMenuItem *launchAtLoginItem;
@property MicStatusView *tx1Value, *tx2Value;
@property NSPopUpButton *gainPopup, *noisePopup, *audioModePopup;
@property NSTextField *controlStatus;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification; self.tx1Battery = self.tx2Battery = self.gain = self.noise = -1;
    self.desiredAudioMode = [[NSUserDefaults standardUserDefaults] integerForKey:kAudioModeDefaultsKey] == 1 ? 1 : 0;
    self.hidQueue = dispatch_queue_create("io.github.bluecoconut.LarkM2Status.hid", DISPATCH_QUEUE_SERIAL);
    [self buildMenu]; [self updateLaunchAtLoginItem]; [self refresh:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.75 target:self selector:@selector(refresh:) userInfo:nil repeats:YES];
}
- (void)buildMenu {
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 188)];
    NSStackView *root = [[NSStackView alloc] init]; root.orientation = NSUserInterfaceLayoutOrientationVertical; root.alignment = NSLayoutAttributeWidth; root.spacing = 1; root.translatesAutoresizingMaskIntoConstraints = NO; [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:11], [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-11], [root.topAnchor constraintEqualToAnchor:content.topAnchor constant:5], [root.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-5]]];
    self.tx1Value = [[MicStatusView alloc] init]; self.tx2Value = [[MicStatusView alloc] init];
    self.gainPopup = Popup(@[@"0 · Quietest", @"1", @"2", @"3", @"4", @"5 · Loudest"], @selector(gainChanged:), self, 142);
    self.noisePopup = Popup(@[@"Off", @"Weak", @"Strong"], @selector(noiseChanged:), self, 142);
    self.audioModePopup = Popup(@[@"Mono · Compatible", @"Stereo · Mic 1 L / Mic 2 R"], @selector(audioModeChanged:), self, 174);
    [self.audioModePopup selectItemAtIndex:self.desiredAudioMode];
    self.controlStatus = Label(@"", 10, NSFontWeightRegular); self.controlStatus.textColor = NSColor.secondaryLabelColor;
    NSStackView *details = [NSStackView stackViewWithViews:@[
        InfoRow(@"Mic 1", self.tx1Value), InfoRow(@"Mic 2", self.tx2Value),
        InfoRow(@"Gain", self.gainPopup), InfoRow(@"Noise cancellation", self.noisePopup),
        InfoRow(@"USB audio", self.audioModePopup), self.controlStatus
    ]];
    details.orientation = NSUserInterfaceLayoutOrientationVertical; details.alignment = NSLayoutAttributeWidth; details.spacing = 1; [root addArrangedSubview:details];
    self.menu = [[NSMenu alloc] initWithTitle:@""]; NSMenuItem *contentItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""]; contentItem.view = content; [self.menu addItem:contentItem]; [self.menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *restart = [[NSMenuItem alloc] initWithTitle:@"Restart Receiver…" action:@selector(restartReceiver:) keyEquivalent:@""]; restart.target = self; [self.menu addItem:restart];
    NSMenuItem *recover = [[NSMenuItem alloc] initWithTitle:@"Restore Mono & Restart…" action:@selector(restoreAndRestart:) keyEquivalent:@""]; recover.target = self; [self.menu addItem:recover];
    [self.menu addItem:NSMenuItem.separatorItem];
    self.launchAtLoginItem = [[NSMenuItem alloc] initWithTitle:@"Launch at Login" action:@selector(toggleLaunchAtLogin:) keyEquivalent:@""]; self.launchAtLoginItem.target = self; [self.menu addItem:self.launchAtLoginItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Lark M2 Status" action:@selector(quit:) keyEquivalent:@"q"]; quit.target = self; quit.keyEquivalentModifierMask = NSEventModifierFlagCommand; [self.menu addItem:quit];
}
- (void)ensureStatusItem { if (self.statusItem) return; self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength]; self.statusItem.menu = self.menu; }
- (void)removeStatusItem { if (!self.statusItem) return; self.statusItem.menu = nil; [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem]; self.statusItem = nil; }
- (void)updateLaunchAtLoginItem {
    self.launchAtLoginItem.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)toggleLaunchAtLogin:(id)sender {
    (void)sender;
    NSError *error = nil;
    if (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) [SMAppService.mainAppService unregisterAndReturnError:&error];
    else [SMAppService.mainAppService registerAndReturnError:&error];
    [self updateLaunchAtLoginItem];
}
- (BOOL)ensureHIDOnQueue {
    if (self.hid) return YES;
    hid_init(); self.hid = hid_open(kLarkVendorID, kLarkProductID, NULL);
    self.audioModeApplied = NO;
    return self.hid != NULL;
}
- (void)closeHIDOnQueue {
    if (self.hid) hid_close(self.hid);
    self.hid = NULL; self.audioModeApplied = NO;
}
- (BOOL)sendStandardCommandOnQueue:(unsigned char)command payload:(const unsigned char *)payload length:(unsigned short)length {
    if (![self ensureHIDOnQueue]) return NO;
    unsigned char request[64]; BuildRequest(request, kStandardReportID, command, 0x40, payload, length);
    unsigned char stale[128]; while (hid_read_timeout(self.hid, stale, sizeof(stale), 0) > 0) {}
    if (hid_write(self.hid, request, sizeof(request)) != sizeof(request)) return NO;
    // Some setters acknowledge and some are intentionally fire-and-forget.
    // Consume an optional acknowledgement so it cannot be mistaken for the next heartbeat.
    unsigned char acknowledgement[128]; (void)hid_read_timeout(self.hid, acknowledgement, sizeof(acknowledgement), 100);
    return YES;
}
- (BOOL)applyAudioModeOnQueue:(NSInteger)mode {
    if (![self ensureHIDOnQueue]) return NO;
    unsigned char request[64], response[64] = {0}; int responseLength = 0;
    BuildProductRequest(request, 0xFF, NULL, 0);
    if (!ProductExchange(self.hid, request, 0xFF, NULL, NULL)) return NO;
    unsigned char value = (unsigned char)mode; BuildProductRequest(request, 0x25, &value, 1);
    if (!ProductExchange(self.hid, request, 0x25, response, &responseLength)) return NO;
    return responseLength >= 1 && response[0] == value;
}
- (void)setControlStatus:(NSString *)text error:(BOOL)error {
    self.controlStatus.stringValue = text ?: @"";
    self.controlStatus.textColor = error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
}
- (void)setControlsEnabled:(BOOL)enabled {
    self.gainPopup.enabled = enabled; self.noisePopup.enabled = enabled; self.audioModePopup.enabled = enabled;
}
- (void)performStandardSetting:(unsigned char)command value:(unsigned char)value successText:(NSString *)successText {
    if (self.controlInFlight) return;
    self.controlInFlight = YES; [self setControlsEnabled:NO]; [self setControlStatus:@"Applying…" error:NO];
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.hidQueue, ^{
        AppDelegate *app = weakSelf; BOOL success = app && [app sendStandardCommandOnQueue:command payload:&value length:1];
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainApp = weakSelf; if (!mainApp) return;
            mainApp.controlInFlight = NO; [mainApp setControlsEnabled:YES];
            [mainApp setControlStatus:success ? successText : @"Receiver did not accept the setting" error:!success];
            if (!success) [mainApp updateInterface];
        });
    });
}
- (void)gainChanged:(NSPopUpButton *)sender {
    unsigned char level = (unsigned char)sender.indexOfSelectedItem;
    [self performStandardSetting:0x05 value:level successText:[NSString stringWithFormat:@"Gain set to %u", level]];
}
- (void)noiseChanged:(NSPopUpButton *)sender {
    if (self.controlInFlight) return;
    NSInteger selection = sender.indexOfSelectedItem;
    self.controlInFlight = YES; [self setControlsEnabled:NO]; [self setControlStatus:@"Applying…" error:NO];
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.hidQueue, ^{
        AppDelegate *app = weakSelf; BOOL success = NO;
        if (app) {
            if (selection == 0) { unsigned char off = 0; success = [app sendStandardCommandOnQueue:0x19 payload:&off length:1]; }
            else {
                unsigned char level = (unsigned char)selection, on = 1;
                success = [app sendStandardCommandOnQueue:0x06 payload:&level length:1];
                if (success) { usleep(25000); success = [app sendStandardCommandOnQueue:0x19 payload:&on length:1]; }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainApp = weakSelf; if (!mainApp) return;
            mainApp.controlInFlight = NO; [mainApp setControlsEnabled:YES];
            NSArray *names = @[@"Off", @"Weak", @"Strong"];
            [mainApp setControlStatus:success ? [NSString stringWithFormat:@"Noise cancellation: %@", names[selection]] : @"Receiver did not accept the setting" error:!success];
            if (!success) [mainApp updateInterface];
        });
    });
}
- (void)audioModeChanged:(NSPopUpButton *)sender {
    if (self.controlInFlight) return;
    NSInteger mode = sender.indexOfSelectedItem == 1 ? 1 : 0;
    self.controlInFlight = YES; [self setControlsEnabled:NO]; [self setControlStatus:@"Changing USB routing…" error:NO];
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.hidQueue, ^{
        AppDelegate *app = weakSelf; BOOL success = app && [app applyAudioModeOnQueue:mode];
        if (success) app.audioModeApplied = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainApp = weakSelf; if (!mainApp) return;
            mainApp.controlInFlight = NO; [mainApp setControlsEnabled:YES];
            if (success) {
                mainApp.desiredAudioMode = mode;
                [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kAudioModeDefaultsKey];
                [mainApp setControlStatus:mode ? @"Stereo active · Mic 1 L / Mic 2 R" : @"Compatible mono active" error:NO];
            } else {
                [mainApp.audioModePopup selectItemAtIndex:mainApp.desiredAudioMode];
                [mainApp setControlStatus:@"USB routing change failed" error:YES];
            }
        });
    });
}
- (void)restartWithMonoRestore:(BOOL)restoreMono {
    if (self.controlInFlight) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = restoreMono ? @"Restore mono and restart the receiver?" : @"Restart the receiver?";
    alert.informativeText = restoreMono ? @"This is the recovery action. It restores compatible duplicated-mono USB audio, clears the temporary product-command state, and restarts the receiver." : @"Audio will disappear briefly. Your selected USB audio mode will be reapplied when the receiver reconnects.";
    [alert addButtonWithTitle:restoreMono ? @"Restore & Restart" : @"Restart"];
    [alert addButtonWithTitle:@"Cancel"];
    [NSApp activateIgnoringOtherApps:YES]; if ([alert runModal] != NSAlertFirstButtonReturn) return;
    if (restoreMono) {
        self.desiredAudioMode = 0; [self.audioModePopup selectItemAtIndex:0];
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:kAudioModeDefaultsKey];
    }
    self.controlInFlight = YES; [self setControlsEnabled:NO]; [self setControlStatus:restoreMono ? @"Restoring mono and restarting…" : @"Restarting…" error:NO];
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.hidQueue, ^{
        AppDelegate *app = weakSelf; BOOL success = app != nil;
        if (success && restoreMono) success = [app applyAudioModeOnQueue:0];
        if (success) { unsigned char request[64]; BuildRequest(request, kStandardReportID, 0x0C, 0x40, NULL, 0); success = [app ensureHIDOnQueue] && hid_write(app.hid, request, sizeof(request)) == sizeof(request); }
        if (app) { usleep(100000); [app closeHIDOnQueue]; }
        dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainApp = weakSelf; if (!mainApp) return;
            mainApp.controlInFlight = NO; [mainApp setControlsEnabled:YES]; mainApp.receiverPresent = NO; [mainApp updateInterface];
            [mainApp setControlStatus:success ? @"Waiting for receiver to reconnect…" : @"Restart command failed" error:!success];
        });
    });
}
- (void)restartReceiver:(id)sender { (void)sender; [self restartWithMonoRestore:NO]; }
- (void)restoreAndRestart:(id)sender { (void)sender; [self restartWithMonoRestore:YES]; }
- (void)refresh:(id)sender {
    (void)sender; if (self.pollInFlight || self.controlInFlight) return; self.pollInFlight = YES; __weak typeof(self) weakSelf = self;
    dispatch_async(self.hidQueue, ^{
        AppDelegate *app = weakSelf; if (!app) return;
        [app ensureHIDOnQueue];
        BOOL valid = NO, tx1 = NO, tx2 = NO; NSInteger battery1 = -1, battery2 = -1, gain = -1, noise = -1;
        if (app.hid) {
            unsigned char request[64] = {0x55, 0xAA, 0xDD, 0x10, 0x40, 0x00, 0x00, 0x27};
            if (hid_write(app.hid, request, sizeof(request)) == 64) {
                unsigned char response[64] = {0}; int count = hid_read_timeout(app.hid, response, sizeof(response), 400); int offset = count > 0 && response[0] == 0x55 ? 1 : 0;
                if (count >= offset + 15 && response[offset] == 0xBB && response[offset + 1] == 0xDD && response[offset + 2] == 0x10 && response[offset + 3] == 0x80 && response[offset + 5] >= 9) {
                    const unsigned char *payload = response + offset + 6; valid = YES; tx1 = payload[0] == 1; tx2 = payload[1] == 1; battery1 = payload[2]; battery2 = payload[3]; noise = payload[6]; gain = payload[7];
                } else { [app closeHIDOnQueue]; }
            } else {
                [app closeHIDOnQueue];
            }
        }
        BOOL routeApplied = NO, routeFailed = NO;
        if (valid && !app.audioModeApplied) {
            if (app.desiredAudioMode == 1) { routeApplied = [app applyAudioModeOnQueue:1]; routeFailed = !routeApplied; }
            else routeApplied = YES;
            app.audioModeApplied = routeApplied;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ AppDelegate *mainApp = weakSelf; if (!mainApp) return; mainApp.pollInFlight = NO; mainApp.receiverPresent = valid; if (valid) { mainApp.tx1Connected = tx1; mainApp.tx2Connected = tx2; mainApp.tx1Battery = battery1; mainApp.tx2Battery = battery2; mainApp.gain = gain; mainApp.noise = noise; } [mainApp updateInterface]; });
        if (routeApplied || routeFailed) dispatch_async(dispatch_get_main_queue(), ^{
            AppDelegate *mainApp = weakSelf; if (!mainApp) return;
            if (routeFailed) [mainApp setControlStatus:@"Could not reapply stereo after reconnect" error:YES];
            else if (mainApp.desiredAudioMode == 1) [mainApp setControlStatus:@"Stereo active · Mic 1 L / Mic 2 R" error:NO];
        });
    });
}
- (void)updateInterface {
    if (!self.receiverPresent) { [self removeStatusItem]; return; }
    [self ensureStatusItem];
    [self.tx1Value setConnected:self.tx1Connected battery:self.tx1Battery]; [self.tx2Value setConnected:self.tx2Connected battery:self.tx2Battery];
    if (self.gain >= 0 && self.gain <= 5 && !self.controlInFlight) [self.gainPopup selectItemAtIndex:self.gain];
    if (self.noise >= 0 && self.noise <= 2 && !self.controlInFlight) [self.noisePopup selectItemAtIndex:self.noise];
    if (!self.controlInFlight) [self.audioModePopup selectItemAtIndex:self.desiredAudioMode];
    self.statusItem.button.image = LarkIcon(); self.statusItem.button.toolTip = [NSString stringWithFormat:@"Lark M2 · Mic 1 %@ · Mic 2 %@", self.tx1Connected ? [NSString stringWithFormat:@"%ld%%", (long)self.tx1Battery] : @"offline", self.tx2Connected ? [NSString stringWithFormat:@"%ld%%", (long)self.tx2Battery] : @"offline"];
}
- (void)quit:(id)sender { (void)sender; [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)notification { (void)notification; [self.timer invalidate]; dispatch_sync(self.hidQueue, ^{ [self closeHIDOnQueue]; hid_exit(); }); }
@end
int main(int argc, const char *argv[]) { (void)argc; (void)argv; @autoreleasepool { NSApplication *app = [NSApplication sharedApplication]; app.activationPolicy = NSApplicationActivationPolicyAccessory; AppDelegate *delegate = [[AppDelegate alloc] init]; app.delegate = delegate; [app run]; } return 0; }
