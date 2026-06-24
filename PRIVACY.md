# Privacy Policy for QuickPlayer

**Last Updated: June 2026**

## Overview

QuickPlayer ("the App") is a music practice tool developed for musicians and singers. This Privacy Policy explains how we handle your information when you use our App.

## Information We Collect

### Information We DO NOT Collect

QuickPlayer is designed with privacy in mind. We do **NOT** collect, store, or transmit:

- Personal identification information (name, email, phone number)
- Location data
- Device identifiers
- Usage analytics
- **Your audio files, recordings, or any audio content you import or process**
- Stem separation results or any audio derived from your files

In particular, the on-device stem separation feature processes your music entirely on your device. Your audio never leaves your phone.

### Information Stored Locally

The following data is stored **only on your device** and never transmitted:

| Data Type | Purpose | Storage Location |
|-----------|---------|------------------|
| Imported audio files | Music playback | Device storage |
| Playback settings | Speed, pitch, EQ, focus mode preferences | App local storage |
| Markers and bookmarks | Practice session management | App local storage |
| A-B loop points | Loop practice feature | App local storage |
| Practice history | Streak / daily practice time tracking | App local storage |
| Metronome BPM + phase per track | Tap-to-sync persistence | App local storage |
| Language preference | UI locale override (or follow-system) | App local storage |
| Stem separation model files | One-time downloaded ML model (~166 MB) | App support directory |
| Stem separation cache | AAC-encoded stems for already-separated songs (~36 MB per song) | App support directory |

## Network Connections

QuickPlayer is functional offline. The App opens an outbound network connection only in the following cases:

### Stem Separation Model Download

The first time you use the stem separation feature, the App downloads the machine-learning model used for separation (approximately 166 MB) from **GitHub Releases** (`github.com`). This is a one-time download per device; subsequent separations run entirely offline.

- The request is a standard HTTPS GET. We do not send any of your audio, account, or device data alongside the request.
- GitHub may log the request's IP address and user-agent per their own terms of service. We do not receive or store these logs.
- You can opt out of this download by simply not using the stem separation feature. All other features of the App work without it.

### Google Play In-App Review

The App may, after substantial practice time has been accumulated, invoke Google Play's **In-App Review** API to ask whether you want to leave a review on the Play Store. The review interaction (including any rating or text you submit) is handled entirely by Google Play; the App neither sees nor stores your review or its outcome.

No other outbound network connections are made by the App.

## Data Storage and Security

- All data is stored locally on your device
- No cloud sync or backup to external servers
- Data is deleted when you uninstall the App
- You can manually delete individual tracks, markers, and cached stems within the App

## Third-Party Services

QuickPlayer integrates with the following third-party services strictly for the purposes described above:

- **GitHub Releases** (`github.com`) — model file distribution. One-way download from us-the-publisher to you-the-user; no user data is sent.
- **Google Play In-App Review** — optional rating prompt, surfaced after a practice milestone is reached. Review handling is performed entirely inside the Play Store; the App does not receive review content.

### Future Updates

Future versions may introduce additional services such as:
- **Google Play Billing**: For in-app purchases (if a paid tier is added in the future)
- **Google AdMob**: Currently NOT integrated; we will update this policy before adding any advertising

If new services are added, this Privacy Policy will be updated accordingly, with the "Last Updated" date reflecting the change.

## Children's Privacy

QuickPlayer does not knowingly collect any personal information from children under the age of 13. The App is designed for general audiences and contains no age-restricted content.

## Your Rights

Since we do not collect personal data, there is no personal information to:
- Access
- Modify
- Delete
- Export

All your data remains on your device under your control.

## Changes to This Policy

We may update this Privacy Policy from time to time. Any changes will be reflected in the "Last Updated" date at the top of this policy. Continued use of the App after changes constitutes acceptance of the updated policy.

## Contact Us

If you have any questions about this Privacy Policy, please contact us at:

**Email**: [YOUR_EMAIL@example.com]

---

## Summary

| Question | Answer |
|----------|--------|
| Do we collect personal data? | No |
| Do we share data with third parties? | No |
| Is your audio uploaded? | No — stem separation runs on your device |
| Does the App make network requests? | Yes, but only to download the stem-separation model from GitHub (one-time) and to invoke Google Play's In-App Review prompt |
| Is data stored on external servers? | No |
| Can you delete your data? | Yes, by uninstalling the App or clearing the cache within the App |

---

*This privacy policy is effective as of June 2026.*
