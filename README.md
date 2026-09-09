# RedTaxi

A ride-hailing platform: **Customer app** (Flutter) · **Driver app** (Flutter) · **Backend API + real-time layer** (Node.js) · **Admin web** (React) · MySQL/MariaDB.

Built by reusing proven infrastructure and dispatch patterns from the internal Microlab
project, with a clean ride/trip domain — no healthcare terminology or lab business logic.

## Repository layout

```
server/       Node.js API + Socket.IO real-time layer   (Phases 2–9 built)
app/          Single Flutter app — customer + driver,    (Phases 2–9 built)
              role chosen at login
database/     schema.sql — authoritative DB design
docs/         BACKEND.md (API + socket contract), APP.md (Flutter layout)
```

No separate admin web — a couple of HMAC-guarded `/ops` endpoints cover
driver KYC approval and fare config.

## Build phases

| Phase | Scope | Status |
|------:|-------|--------|
| 1 | Analysis, architecture, DB design, API design | ✅ done |
| 2 | Auth (customer + driver), profiles | ✅ built |
| 3 | Maps, pickup/destination, route, fare estimate | ✅ built |
| 4 | Ride creation, driver availability, dispatch | ✅ built |
| 5 | Race-safe accept/assign (atomic DB UPDATE + generated-column UNIQUE) | ✅ built |
| 6 | Socket.IO live GPS tracking | ✅ built |
| 7 | Full ride lifecycle (central state machine) | ✅ built |
| 8 | Payment (idempotent, cash + Razorpay) | ✅ built |
| 9 | Rating, history, notifications, driver earnings | ✅ built |
| 10 | Run against a live DB, tests, load, security, data-consistency | ⬜ pending |

"Built" = code written and statically verified (`flutter analyze` clean;
every backend module loads). Not yet run end-to-end against a live database.

## Backend quick start

```bash
cd server
cp .env.example .env          # fill in DB / JWT / SMS / Firebase / Maps values
npm install
npm run migrate               # apply db/migrations
npm run seed                  # optional dev seed data
npm run dev                   # nodemon
```

Requires: Node 20+, MySQL 8 / MariaDB 10.6+, Redis 6+ (optional in dev — in-memory fallback).
