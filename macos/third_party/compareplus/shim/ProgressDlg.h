// The plugin's progress dialog, reduced to what the engine asks of it: a
// counter and a cancel flag. A compare here runs on the main thread and is
// over before a dialog would help; the flag lets a future caller stop one.
#pragma once
#include <memory>
#include <string>
#include <atomic>
#include <exception>

class ProgressDlg;
using progress_ptr = std::shared_ptr<ProgressDlg>;

class ProgressDlg {
public:
    static const std::string cCancelledCause;
    static progress_ptr &Open(const wchar_t *info = nullptr);
    static progress_ptr &Get();
    static void Close();
    void SetInfo(const wchar_t *) const {}
    void Show() const {}
    bool IsCancelled() const { return cancelled.load(); }
    void ThrowIfCancelled() const { if (cancelled.load()) throw std::runtime_error(cCancelledCause); }
    void SetMaxCount(intptr_t, unsigned = 0) {}
    void SetCount(intptr_t, unsigned = 0) {}
    void Advance(intptr_t = 1, unsigned = 0) {}
    void NextPhase() {}
    void Cancel() { cancelled.store(true); }
private:
    std::atomic<bool> cancelled {false};
};
