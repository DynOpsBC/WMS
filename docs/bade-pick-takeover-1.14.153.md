# BADE 1.14.153 — confirmed terminal pick takeover

All terminal pick claim entry points now read the current BC owner. If another
operator owns the document, a dialog shows the pick number and owner and asks
“Belgeyi devralmak istediğinize emin misiniz?”. “Vazgeç” does not write anything.
“Evet, Bana Ata” uses the existing BC `forceReassign(userId, reason)` action with the
signed-in terminal operator, then reads ownership back before reporting success.
Unassigned picks continue through `claim`. No shared-BC-account fallback exists.

Ownership is reread after confirmation; a changed owner requires a new attempt.
The existing AL reassignment transaction logs the transfer and synchronizes the
picking order owner. BC 1.14.1.64 supports this action; no AL upgrade is needed.
The existing action is unconditional once invoked: the client recheck does not
provide an atomic expected-owner condition against a simultaneous later reassignment.

Unit coverage includes accept/cancel, unassigned/same owner, owner changing while
the dialog is open, malformed ownership, failed writes, and false server success.
The Compose test opens the actual confirmation dialog, cancels, reopens, and accepts.
No existing customer production document is reassigned during automated validation.

Validation: 443 BADE unit tests passed, zero failures/errors. BADE debug lint
and signed release build passed. PickTakeoverUiTest passed on the emulator
(1 test, 11.393 seconds). The release APK contains the confirmation UI and
forceReassign action and retains the previous release signing certificate.
