-- Legal documents for the Python + Flet app: Terms of Use, a Privacy Policy that describes this app
-- (the previous notice described the web app's GPS runs and browser downloads), and a Cookie and
-- Local Storage Policy. They live in privacy_notices like every other notice, so they are versioned,
-- immutable once published, and accepted through the same user_consents records.
--
-- Accepting the Terms is recorded like acknowledging the privacy notice. The cookie policy needs no
-- consent (the app sets no cookies), so it is published for reading only.

ALTER TABLE public.privacy_notices DROP CONSTRAINT privacy_notices_consent_type_check;
ALTER TABLE public.privacy_notices ADD CONSTRAINT privacy_notices_consent_type_check CHECK (consent_type = ANY (ARRAY[
  'privacy_notice', 'camera', 'gps', 'ai_features', 'relative_leaderboard', 'verification', 'training_limits',
  'terms_of_use', 'cookie_policy']));

CREATE OR REPLACE FUNCTION public.record_consent(p_user_id uuid, p_consent_type text, p_notice_version text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
  v_current TEXT;
  v_row     public.user_consents%ROWTYPE;
BEGIN
  IF p_consent_type NOT IN ('privacy_notice', 'terms_of_use', 'camera', 'gps', 'ai_features', 'verification') THEN
    RAISE EXCEPTION 'INVALID_CONSENT_TYPE: % is not an acknowledgement notice', p_consent_type;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'UNKNOWN_USER: account not found';
  END IF;

  v_current := public.current_notice_version(p_consent_type);
  IF v_current IS NULL OR p_notice_version IS DISTINCT FROM v_current THEN
    RAISE EXCEPTION 'NOTICE_VERSION_OUTDATED: this notice has been updated. Please read the current version.';
  END IF;

  SELECT * INTO v_row FROM public.user_consents
  WHERE user_id = p_user_id AND consent_type = p_consent_type
  ORDER BY acknowledged_at DESC, id DESC LIMIT 1;

  IF NOT FOUND OR v_row.notice_version <> v_current THEN
    INSERT INTO public.user_consents (user_id, consent_type, notice_version, decision)
    VALUES (p_user_id, p_consent_type, v_current, 'acknowledged')
    RETURNING * INTO v_row;
  END IF;

  RETURN jsonb_build_object('consent_type', v_row.consent_type, 'notice_version', v_row.notice_version,
                            'decision', v_row.decision, 'acknowledged_at', v_row.acknowledged_at);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.record_consent(uuid, text, text) FROM PUBLIC, anon, authenticated;

INSERT INTO public.privacy_notices (consent_type, version, title, body, is_draft) VALUES
('terms_of_use', '2026-10-16.v1', 'Terms of Use', $doc$Effective 16 October 2026.

These Terms of Use ("Terms") are an agreement between you and the AWXCEND development team ("AWXCEND", "we", "us"). AWXCEND is a free, non-commercial fitness app made as a student project. By creating an account or using the app, you agree to these Terms and to our Privacy Policy. If you do not agree, do not use AWXCEND.

## 1. Who can use AWXCEND
- You must be **at least 18 years old**. You confirm your age when you sign up. If we learn that an account belongs to someone under 18, we will close it and delete its data.
- You must be able to enter into a binding agreement under the laws of the Philippines or of the place where you live.
- You may not use AWXCEND if we have permanently banned you.

## 2. Your account
- Give true information when you sign up, and keep your password secret. You are responsible for what happens under your account.
- One person, one account. Do not sell, share or transfer accounts.
- Tell us through **Profile > Account & privacy > Report a problem** if you think someone else has used your account.

## 3. Health and safety
- **AWXCEND is not a medical service.** Workouts, plans, XP goals, nutrition figures, AI coach suggestions and camera rep counts are general information, not medical, dietary or professional advice.
- Talk to a doctor before starting a new exercise or diet program, especially if you are pregnant, injured, or have a heart, blood-pressure, joint or other medical condition.
- Stop exercising and get medical help if you feel pain, dizziness, chest pain or shortness of breath.
- You exercise **at your own risk**. Train within your limits, use proper form and equipment, and make sure your space is safe, especially when using the camera.
- Nutrition values are estimates and can be wrong. Camera rep counting can miss or add reps. Check what matters to you yourself.

## 4. Community rules
When you post, chat, message or report, you must not:
- harass, threaten, bully, stalk or shame anyone, including gender-based online sexual harassment under the Safe Spaces Act (Republic Act No. 11313);
- post anything defamatory or libelous (including cyber libel under the Cybercrime Prevention Act, Republic Act No. 10175), hateful, sexually explicit, violent, or illegal;
- share another person's personal information, photos or private messages without their permission;
- impersonate anyone, or pretend to be AWXCEND staff;
- post spam, scams, advertising, or links to malware;
- promote dangerous practices such as steroid or drug misuse, extreme dieting, or eating disorders;
- post content you do not have the right to share.

## 5. Fair play and security
You must not:
- fake workouts or stats, use bots or scripts, or exploit bugs to gain XP, gold, ranks or items;
- access accounts, data or systems that are not yours, or try to get around rate limits, bans or other protections;
- overload, attack, scan or disrupt the app or its servers, or reverse engineer it to do any of these.
Report security problems to us privately through Report a problem instead of using or sharing them.

## 6. Moderation
- Moderators and admins may review reported content and accounts, remove content, and restrict or ban accounts for breaking these Terms. A sanction shows its reason and end date.
- A sanction never stops you from downloading or deleting your own data.
- We are not required to monitor everything posted, and we are not responsible for what other users post. Use Report on anything that breaks these rules.

## 7. Your content
- You keep ownership of what you post (text and photos).
- You give AWXCEND a free, non-exclusive licence to store, display and share it inside the app, only so the app can work. This licence ends when you or we delete the content, except copies that other users already received in chat or messages.
- Do not post content that infringes anyone's copyright, trademark or other rights under the Intellectual Property Code (Republic Act No. 8293). We remove infringing content when we are told about it.

## 8. Game items
XP, levels, ranks, gold, potions, titles and other game items have **no money value**. They cannot be bought, sold or exchanged for money, and we may change or reset them, for example to fix a bug or stop cheating.

## 9. Third-party services
AWXCEND uses outside services to work, as listed in the Privacy Policy (for example Supabase for data, Brevo for email and USDA FoodData Central for food search). We are not responsible for those services, and their own terms apply to them.

## 10. The service is provided "as is"
AWXCEND is a free student project. To the extent the law allows, it is provided **"as is" and "as available"**, without warranties of any kind. We do not promise that the app will always be available, error-free or secure, that data will never be lost, or that results will meet your goals. Features can change or stop, and the AI coach may be offline.

## 11. Limitation of liability
To the extent the law allows, AWXCEND and its developers are not liable for any injury, health problem, loss of data, or indirect or consequential damage that comes from using or not being able to use the app, from following any content in it, or from other users' conduct. Nothing in these Terms limits liability that cannot be limited by law, such as liability for fraud, bad faith or gross negligence.

## 12. Your responsibility
If you break these Terms or the law while using AWXCEND, you agree to be responsible for the resulting claims and costs against AWXCEND and its developers, to the extent the law allows.

## 13. Ending your account
- You can delete your account at any time from Profile > Account & privacy.
- We may suspend or close an account that breaks these Terms or the law, or to protect users or the service.
- We may end AWXCEND as a whole. If we do, we will try to tell you in the app first.

## 14. Changes to these Terms
We may update these Terms. When we do, the app shows the new version and asks you to accept it before you continue. If you do not accept, you can delete your account.

## 15. Governing law
These Terms are governed by the laws of the Republic of the Philippines, including the Electronic Commerce Act (Republic Act No. 8792), which makes accepting them in the app valid. Disputes go to the proper courts of the Philippines, unless the law where you live gives you rights that cannot be taken away.

## 16. Contact
Profile > Account & privacy > Report a problem.$doc$, false),

('privacy_notice', '2026-10-16.v1', 'Privacy Policy', $doc$Effective 16 October 2026.

This Privacy Policy explains what personal information the AWXCEND app (Windows and Android) collects, why, who receives it, and your rights under the **Data Privacy Act of 2012 (Republic Act No. 10173)**, its Implementing Rules, and the issuances of the National Privacy Commission (NPC). The AWXCEND development team is the personal information controller.

## 1. What we collect
**You give us:**
- Account: email address, password (stored only as a secure hash by our login provider), username and bio.
- Body information: bodyweight, height, age (required, to confirm you are 18 or over), sex and goal. Body and health information is **sensitive personal information** under the Data Privacy Act, and we process it only with your consent.
- Activity: workouts (exercise, sets, reps, weight, time), routines, training plan answers and progress, XP, ranks, missions, gold, items and personal records.
- Meals: foods, amounts and nutrition you log, and food budget entries.
- Social: posts and photos, chat and direct messages, friend requests, reports and bug reports you send.
- Areas to go easy on, only if you choose to turn this on.

**Created while you use the app:**
- Login records and security logs kept by our backend provider (for example sign-in times and IP address), moderation records, and an audit log of moderator actions.

**What stays on your device and is never uploaded:**
- **Camera video.** Pose detection runs on your computer. Video is never recorded, saved or sent.
- Camera practice recordings: the desktop app saves the joint positions (numbers only, no images) of each camera set in the "AWXCEND sessions" folder in your home folder, to improve rep counting. You can delete that folder at any time.
- Your login session and app settings (see the Cookie and Local Storage Policy).

## 2. Why we use it (purpose and legal basis)
- To run your account and the app's features: XP, ranks, plans, food log, community. *Basis: our agreement with you (the Terms).*
- To estimate calorie and plan targets from your body information. *Basis: your consent, given at sign-up.*
- To keep the community safe: moderation, reports, rate limits and security logs. *Basis: our legitimate interest in a safe service, and legal obligations.*
- To answer your bug reports and requests.
- We **do not sell** your data, show ads, or use your data for marketing or profiling outside the app.

## 3. Who can see it
- **Other users** see your username, bio, rank, level, stats, recent workouts on your profile, your lifts on the strength leaderboard, and what you post in the community and chat. Photos you post are stored at a public web address that anyone with the link can open.
- **Other users never see** your email, bodyweight, height, age, sex or goal. The bodyweight-relative leaderboard shows you only if you join it.
- **Moderators and admins** see reports, posts waiting for approval, and account lists with roles, and can issue sanctions. Every sanction is logged.

## 4. Service providers and transfers outside the Philippines
We use these providers to run the app. They process data only to provide their service:
- **Supabase** (database, login, file storage, server functions): stores all account data. Its servers are outside the Philippines.
- **Brevo** (email): receives your email address to send password-reset emails.
- **USDA FoodData Central** (United States): receives the food names you search for, not your identity.
- **AI coach:** when you choose to use it, your recent workouts, meals, goals and targets are sent to a self-hosted AI model on a developer's computer through an ngrok tunnel. You are asked first.
- **GitHub** hosts the app downloads.
By using AWXCEND you understand that your data is processed outside the Philippines. We stay responsible for it under the Data Privacy Act.

## 5. How long we keep it
- Your data is kept while your account exists.
- When you delete your account, your profile, workouts, meals, routines, posts, photos and messages are deleted. Direct messages are deleted for both people. Reports you filed are kept without your name so moderation decisions stay explainable.
- Security and moderation logs are kept only as long as needed to protect the service.
- Copies in our providers' backups are removed on their normal backup cycle.

## 6. How we protect it
Encrypted connections (HTTPS), hashed passwords, Row Level Security on every database table, server-side checks on every action, role-based access for moderators and admins, rate limits, and audit logs. No method is perfectly secure. If a personal data breach puts you at real risk, we will notify you and the NPC as the law requires (within 72 hours of knowing about it).

## 7. Your rights
Under the Data Privacy Act you have the right to:
- **be informed** about how your data is processed (this policy);
- **access** your data: Profile > Account & privacy > Download my data;
- **correct** it: edit your profile at any time;
- **erase or block** it: delete your account, or hide it to keep your data but stop others seeing you;
- **object** and **withdraw consent**: stop using a feature, leave the relative leaderboard, or delete your account. Withdrawing consent does not affect processing done before;
- **data portability**: your download is a machine-readable JSON file;
- **damages** if you are harmed by inaccurate, unlawfully obtained or unauthorised use of your data;
- **file a complaint** with the National Privacy Commission (privacy.gov.ph).
These rights work even if your account is restricted or banned.

## 8. Age limit
AWXCEND is for people **18 and over**. We do not knowingly collect data from anyone younger. If you think a minor has an account, report it and we will delete it.

## 9. Changes
When this policy changes, the app shows the new version and asks you to read it before you continue.

## 10. Contact
For privacy questions or to exercise your rights: Profile > Account & privacy > Report a problem.$doc$, false),

('cookie_policy', '2026-10-16.v1', 'Cookie and Local Storage Policy', $doc$Effective 16 October 2026.

## Cookies
The AWXCEND app (Windows and Android) **does not use cookies**. It has no advertising, analytics or tracking tools, and no third party can place trackers through it.

## What the app stores on your device
Like any app, AWXCEND keeps a few things on your device so it works. These are strictly necessary and are never used to track you:

- **Login session** (access and refresh tokens): keeps you signed in. Kept until you sign out or the session expires.
- **Camera choices** (which camera, phone address, rotation), desktop only: remembers your camera setup. Kept until you change them or remove the app.
- **Camera practice recordings** (the "AWXCEND sessions" folder), desktop only: joint-position numbers used to improve rep counting. Kept until you delete the folder.

## Servers
When the app talks to our servers, our providers (Supabase, and Brevo for email) receive technical information every internet connection needs, such as your IP address, and may keep it in security logs. See the Privacy Policy.

## Your choices
- Sign out to remove your login session from the device.
- Delete the "AWXCEND sessions" folder in your home folder to remove camera recordings.
- Uninstalling the app removes the rest.

## Changes
If the app ever starts using cookies or similar tools (for example in a web version), this policy will be updated first and you will be told in the app.$doc$, false);
