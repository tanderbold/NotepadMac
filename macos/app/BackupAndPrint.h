// Backup, autosave and the print options behind Preferences > Backup and Print.
#import "EditorController.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NppBackupMode) {
    NppBackupNone = 0,      // no backup on save
    NppBackupSimple,        // file.ext.bak beside the file
    NppBackupVerbose,       // timestamped copy in the backup directory
};

typedef NS_ENUM(NSInteger, NppPrintColourMode) {
    NppPrintWYSIWYG = 0,    // colours as shown
    NppPrintInvert,         // inverted
    NppPrintBlackOnWhite,   // plain black text
    NppPrintNoBackground,   // colours kept, background dropped
};

@interface EditorController (BackupAndPrint)

// Backup
- (NSString *)backupDirectory;
/// Makes the backup the current mode calls for; returns the file written, or nil.
- (nullable NSString *)writeBackupForPath:(NSString *)path;
- (NSArray<NSString *> *)backupsForPath:(NSString *)path;

// Autosave and session snapshots
- (void)setAutosaveEnabled:(BOOL)enabled interval:(NSTimeInterval)seconds;
- (BOOL)autosaveRunning;
/// One backup pass: writes the unsaved text of every modified document to
/// its own file in the backup folder - never the file itself - and saves the
/// session, which lists the backups. Returns how many backups were written.
- (NSUInteger)runAutosavePass;

// Print
/// Expands the $(...) variables Notepad++ allows in headers and footers.
- (NSString *)expandPrintTemplate:(NSString *)tpl page:(NSInteger)page of:(NSInteger)pages;
/// The text as it will be printed, with line numbers when that is switched on.
- (NSString *)textForPrinting;
- (NSPrintInfo *)printInfoFromPreferences;
/// The print job, built from Preferences: margins, colours, line numbers and
/// the header and footer templates.
- (nullable NSPrintOperation *)printOperationShowingPanel:(BOOL)showPanel;

@end

NS_ASSUME_NONNULL_END
