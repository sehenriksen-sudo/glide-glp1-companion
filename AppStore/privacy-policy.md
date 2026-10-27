# Privacy Policy — Glide GLP-1 Tracker

**Last updated: October 27, 2026**

Glide ("we", "us", "our") is committed to protecting your privacy. This policy explains what data
Glide collects, how it is used, and what choices you have. We have written it in plain language
on purpose — if anything is unclear, contact us at the address below.

---

## 1. The short version

- **Your health data never leaves your device.** Medication logs, weight entries, food logs, and
  exercise records are stored locally using Apple's SwiftData framework and are never uploaded to
  our servers.
- **Community features are fully anonymous.** If you use the optional community chat, you connect
  through a randomly assigned anonymous ID — no name, email, or phone number is required or collected.
- **We do not sell your data.** Ever. To anyone.
- **You can delete everything at any time** by deleting the app.

---

## 2. Data stored on your device

The following data is created and stored exclusively on your iPhone. It never leaves your device
unless you explicitly choose to export it (e.g. via the CSV export feature):

| Data type | What it contains |
|---|---|
| Medication logs | Injection date, dose, medication type |
| Weight logs | Date and weight measurement |
| Food logs | Meal name, calories, macronutrients |
| Exercise logs | Workout type, duration, calories, distance |
| User configuration | Medication preference, goal weight, cost settings |
| Community profile | Display name, bio, profile photo, GLP-1 start date |

This data is protected by your device's standard security (Face ID / passcode encryption).

---

## 3. Apple HealthKit

Glide can read workout data from Apple Health with your explicit permission. We use this data
solely to populate the exercise log inside the app. In accordance with Apple's requirements:

- HealthKit data is **never used for advertising** or shared with data brokers.
- HealthKit data is **never sold** to third parties.
- HealthKit data is **never used for any purpose other than** providing exercise tracking features
  within Glide.
- You can revoke HealthKit access at any time in **Settings → Privacy & Security → Health → Glide**.

---

## 4. Community chat (optional, anonymous)

The community chat feature is opt-in and anonymous. If you choose to use it:

**Firebase Anonymous Authentication**
We use Google Firebase to assign you a randomly generated anonymous ID. This ID has no connection
to your name, email, Apple ID, or any other identifier. Firebase may log basic technical data
associated with this ID (e.g. sign-in timestamps, IP address) as described in
[Google's Privacy Policy](https://policies.google.com/privacy).

**Firebase Firestore**
Your community profile (display name, bio, GLP-1 medication type, weeks on journey, and optionally
a profile photo) is stored in Firebase Firestore and is visible to other users while you are active
in the community. This profile contains no contact information or real identity.

**Firebase Storage**
If you upload a profile photo, it is stored in Firebase Storage linked only to your anonymous ID.

**Chat messages**
Messages are stored in Firestore only for the duration of an active chat session. When either
participant disconnects, the chat room is marked inactive. We do not retain message history beyond
the active session.

**What we do not collect in community:**
No email address, phone number, Apple ID, real name, location, or device identifier is associated
with your community profile.

---

## 5. Subscriptions (RevenueCat)

Glide uses RevenueCat to manage Premium subscriptions. When you make a purchase, RevenueCat
processes the transaction through Apple's App Store. RevenueCat may collect:

- Purchase history and subscription status
- A device-level anonymous identifier

RevenueCat does not receive your name, email, or payment details — those remain with Apple.
See [RevenueCat's Privacy Policy](https://www.revenuecat.com/privacy) for details.

---

## 6. Crash reporting and analytics

Glide **does not** include any third-party analytics SDK (e.g. Mixpanel, Amplitude, Firebase
Analytics). We do not track in-app behaviour, screen views, or usage patterns.

Apple may collect anonymised crash reports through the App Store if you have opted in to
"Share with App Developers" in your iPhone settings. We use these crash reports solely to fix bugs.

---

## 7. Data sharing

We do not sell, rent, or share your personal data with third parties except:

- **Apple** — as required to process App Store purchases and deliver the app.
- **Google Firebase** — only for anonymous community chat sessions, as described in section 4.
- **RevenueCat** — only for subscription management, as described in section 5.
- **Legal requirements** — if we are required to disclose information by law, court order, or
  governmental authority.

---

## 8. Children's privacy

Glide is rated 12+ on the App Store. We do not knowingly collect data from children under 13.
If you believe a child under 13 has used the community features, contact us and we will remove
their data promptly.

---

## 9. Your rights

**Delete your data**
Delete the app from your iPhone to permanently erase all on-device data. To delete your anonymous
Firebase community profile, use the in-app profile settings or contact us.

**Export your data**
Use Settings → Export Data in the app to download a CSV of all your logs at any time.

**Access and portability**
Because your health data is stored on your device, you have direct access to it at all times.

**GDPR (European users)**
If you are in the European Economic Area, you have the right to access, correct, port, and erase
your personal data, and to object to or restrict its processing. Contact us to exercise these rights.

**CCPA (California users)**
We do not sell personal information. California residents may request disclosure of data categories
collected and shared. Contact us to make a request.

---

## 10. Data retention

| Data | Retention |
|---|---|
| On-device health logs | Until you delete the app or the data manually |
| Community profile (Firebase) | Until you delete it in-app or contact us |
| Chat messages (Firebase) | Session only — marked inactive on disconnect |
| Anonymous Firebase auth ID | Until you contact us requesting deletion |
| RevenueCat purchase records | Per RevenueCat's retention policy |

---

## 11. Security

- On-device data is encrypted by iOS at rest.
- Firebase data is transmitted over TLS and stored in Google's infrastructure.
- Your community profile is accessible only via your anonymous Firebase auth token.
- We do not store passwords because no account is required.

---

## 12. Changes to this policy

We may update this policy from time to time. When we do, we will update the "Last updated" date
at the top of this page and post the new version at the URL below. For material changes, we will
notify you via an in-app notice.

---

## 13. Contact

Questions or requests regarding your privacy:

**Email:** privacy@glideapp.io *(update with your real address before publishing)*
**Website:** https://glideapp.io/privacy *(update with your real URL — required by App Store)*

---

*Glide is an informational tool and is not a medical device. It is not intended to diagnose,
treat, cure, or prevent any disease. Always follow your prescriber's guidance.*
