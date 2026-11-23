# RoomOptima

Predictive room allocation and intelligent scheduling for Gordon College, College of Computer Studies.
BSCS 3-C · Team Falcons Philippines

A front-end website backed by Supabase. It has no build step, but must be served from a local or deployed web server (not opened as a `file://` URL).

## Supabase setup

1. In the Supabase Dashboard for this project, open **SQL Editor**, paste in `supabase/setup.sql`, and run it. This creates the tables, starter rooms, public availability view, and row-level security policies.
2. In **Authentication → Users**, create the accounts that should be able to sign in. New accounts are assigned the Student role and get a profile automatically. If email confirmation is enabled, confirm each account before signing in. Set profile details in RoomOptima after signing in.
3. To grant administrator access, run this in the SQL Editor using the administrator's exact email:

   ```sql
   update public.profiles
   set role = 'admin'
   where email = 'admin@gordoncollege.edu.ph';
   ```

   Only trusted project administrators should be promoted. The old sample credentials were browser-only demo accounts and are not automatically created in Supabase; use strong passwords when creating accounts.
4. Serve the project from `http://localhost` while developing (for example, `python -m http.server 8000` from the project directory). Add your localhost and production origins in the Supabase project's authentication URL configuration.

The browser uses the project's public anon key. It is not a secret; access is controlled by the row-level security policies in the SQL setup. Never put a Supabase `service_role` key in this frontend.

## Project structure

```
roomoptima/
├── index.html            Page markup: landing page, login screen, app shell, modal roots
├── supabase/
│   └── setup.sql         Supabase tables, starter rooms, view, triggers and RLS policies
├── assets/
│   └── seal.png          Gordon College seal
├── css/
│   ├── tokens.css        Colours, fonts, light and dark palettes
│   ├── base.css          Reset and typography
│   ├── components.css    Buttons, badges, fields, cards, tables, modals, toasts
│   ├── layout.css        Login screen, sidebar, top bar
│   ├── landing.css       Landing page
│   ├── pages.css         Rooms, schedule grid, recommendations, profile
│   └── responsive.css    Breakpoints and reduced motion
└── js/
    ├── utils.js          DOM and date/time helpers
    ├── config.js         Supabase connection, equipment, buildings, time slots, icons
    ├── store.js          Supabase data layer and lookups
    ├── ui.js             UI state, HTML builders, modals, toasts
    ├── forms.js          Inline validation engine and shared validators
    ├── policy.js         Terms and Room Use Policy text
    ├── auth.js           Sign in, sign out, switching between landing, login and app
    ├── router.js         Hash routing and sidebar
    ├── pages/
    │   ├── dashboard.js  Administrator and student dashboards
    │   ├── rooms.js      Rooms, room details, add/edit room
    │   ├── bookings.js   Bookings, booking dialog, cancellation dialog
    │   ├── schedule.js   Schedule grid
    │   ├── recommend.js  Smart recommendation
    │   ├── settings.js   Admin settings and bulk actions
    │   └── profile.js    Profile and login information
    ├── landing.js        Landing page: today's room board, rules, buildings
    ├── actions.js        Submit handlers and click actions
    └── main.js           Start-up
```

Scripts are plain files loaded in order by `index.html` (see the `<script>` list at the bottom). The Supabase JavaScript client is loaded first; the other scripts share one scope, so order matters: `utils`, `config`, `store`, `ui`, `forms`, then everything else, and `main.js` last.

## How the 12 revisions are covered

| Revision | Where |
| --- | --- |
| Input validation, bad validation | `js/forms.js` and the validators in each page file; errors show under the field |
| Dates (start and end) | Booking dialog in `js/pages/bookings.js` |
| Terms and conditions, policies | `js/policy.js`; checkbox on Login, New Booking and Cancel Booking |
| Identity of Gordon College | Seal, college name and CCS line in `index.html` |
| Proper naming convention | `nameErr` in `js/forms.js` (Last Name, First Name M.I.); "Room 301" labels |
| Location and room details | Detail panel and floor map in `js/pages/rooms.js` |
| Profile and login info | `js/pages/profile.js` |
| Equipment dropdown | Multi-select in the room dialog; filters on Rooms and Smart Recommend |
| Room number: not everything | Digits only, 2 to 4 long, unique (`js/pages/rooms.js`) |
| Limit capacity | Group size must not exceed the room capacity (`js/pages/bookings.js`) |
| Modal cancellation | `openCancel` in `js/pages/bookings.js`; all dialogs close with ✕, Cancel, Esc or a click outside |

## Data

Rooms, bookings, profiles, and booking policy are stored in Supabase. The SQL setup seeds the starter rooms and policy; bookings start empty. Existing browser-only records and demo accounts are not automatically imported—create Supabase Auth users and re-enter any data you want to keep. The landing page reads a restricted schedule view that contains availability only; signed-in students can access their own booking details, while administrators can manage all records. Auth sessions are stored in the browser according to the “Keep me signed in” checkbox. Data access is in `js/store.js`.

The policy text in `js/policy.js` and the building names in `js/config.js` are samples. Replace them with the college's real details.
