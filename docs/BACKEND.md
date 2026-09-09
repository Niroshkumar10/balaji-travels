# RedTaxi backend — API & realtime contract

Base URL: `/api/v1` · Auth: `Authorization: Bearer <jwt>` (from `/auth/otp/verify`).
Errors: `{ "error": { "code", "message", "details?" } }` with the matching HTTP status.

## REST

### auth
| Method | Path | Role | Body | Notes |
|---|---|---|---|---|
| POST | `/auth/otp/request` | – | `{ mobile, role }` | `role` = `customer`\|`driver`. Returns `devCode` when `NODE_ENV != production`. Rate-limited. |
| POST | `/auth/otp/verify` | – | `{ mobile, role, code }` | → `{ token, isNewUser, user, profile }`. Creates the identity + profile on first success. |
| POST | `/auth/logout` | any | – | Revokes the current token (and sets driver offline). |
| POST | `/auth/fcm-token` | any | `{ fcmToken }` | |
| GET | `/auth/me` | any | – | Echoes `{ userId, role, profileId }`. |

### customers
| GET | `/customers/me` | customer | profile (user + customer) |
| PATCH | `/customers/me` | customer | `name, email, defaultPaymentMethod, home*/work* (label/lat/lng/addr)` |

### drivers
| GET | `/drivers/me` | driver | profile (user + driver + vehicles) |
| PATCH | `/drivers/me` | driver | `name, email, licenseNo` |
| GET | `/drivers/me/vehicles` | driver | |
| POST | `/drivers/me/vehicle` | driver | `{ category, plateNo, make?, model?, color?, year? }` |
| POST | `/drivers/me/online` | driver | `{ lat, lng }` — requires KYC approved + active vehicle |
| POST | `/drivers/me/offline` | driver | blocked while on an active ride |
| POST | `/drivers/me/heartbeat` | driver | `{ lat, lng, bearing?, speedKmph?, battery? }` |

### rides
| POST | `/rides/estimate` | any | `{ pickup:{lat,lng,addr?}, drop, categories? }` → `{ route, options:[{category,fare,breakdown}] }` |
| POST | `/rides` | customer | `{ pickup, drop, vehicleCategory, rideType?, paymentMethod?, promoCode? }` → ride (status `SEARCHING_DRIVER`); dispatch starts |
| GET | `/rides/active` | any | current ride or `null` |
| GET | `/rides?limit&offset` | any | ride history |
| GET | `/rides/:id` | owner | ride (+ driver/vehicle/location when assigned) |
| GET | `/rides/:id/history` | owner | status-transition audit |
| POST | `/rides/:id/cancel` | owner | `{ reason? }` |
| POST | `/rides/:id/offer-response` | driver | `{ accept }` — REST fallback for the dispatch offer |
| POST | `/rides/:id/enroute` \| `/arrived` | driver | trip milestones |
| POST | `/rides/:id/start` | driver | `{ otp }` (4 digits from the customer) |
| POST | `/rides/:id/complete` | driver | `{ waitingMinutes? }` → computes final fare, moves to `PAYMENT_PENDING` |

### payments
| POST | `/payments/rides/:id/order` | customer | create Razorpay order for UPI/card (`Idempotency-Key` header honoured) |
| POST | `/payments/rides/:id/confirm` | customer | `{ orderId, paymentId, signature }` after checkout |
| POST | `/payments/rides/:id/cash` | driver | confirm cash collected → ride `COMPLETED`, driver credited |
| GET | `/payments/rides/:id` | owner | latest payment row |
| POST | `/payments/webhook` | – | Razorpay webhook (signature-verified, event-deduped) |

### ratings / earnings / promos / places / notifications
| POST | `/ratings/rides/:id` | owner | `{ stars 1..5, comment?, tags? }` (ride must be `COMPLETED`, one per side) |
| GET | `/earnings/summary?period=day\|week\|month\|all` | driver | |
| GET | `/earnings/ledger` · `/earnings/payouts` · POST `/earnings/payout` `{ amount }` | driver | |
| GET | `/promos` · POST `/promos/apply` `{ code, fare }` | customer | |
| GET | `/places/autocomplete?q&lat&lng` · `/places/reverse?lat&lng` · `/places/details?placeId` | any | proxied (maps key stays server-side) |
| GET/POST/DELETE | `/places/saved` | customer | saved locations |
| GET | `/notifications` · POST `/notifications/:id/read` · `/notifications/read-all` | any | |

### ops (HMAC only — `X-Admin-Signature`, `X-Admin-Timestamp`)
`GET /ops/drivers?kyc=` · `POST /ops/drivers/:driverId/kyc {status,reason?}` · `GET /ops/rides?status=` · `POST /ops/fare-config {...}`

## Socket.IO

Connect: `io(url, { auth: { token } })`. Identity is fixed at the handshake — no event payload carries an id. Rooms: `user:<userId>`, `ride:<rideId>`.

### client → server (with ack `{ ok, ... }`)
| Event | Role | Payload |
|---|---|---|
| `ping` | any | – |
| `ride:request` | customer | `{ pickup, drop, vehicleCategory, rideType?, paymentMethod?, promoCode? }` |
| `ride:cancel` | customer | `{ rideId, reason? }` |
| `ride:resync` | any | `{ rideId }` → authoritative snapshot |
| `customer:location` | customer | `{ rideId, lat, lng }` |
| `driver:online` / `driver:offline` / `driver:heartbeat` | driver | `{ lat, lng, ... }` |
| `ride:offer_response` | driver | `{ rideId, accept }` |
| `ride:enroute` / `ride:arrived` | driver | `{ rideId }` |
| `ride:start` | driver | `{ rideId, otp }` |
| `ride:complete` | driver | `{ rideId, waitingMinutes? }` |
| `driver:location` | driver | `{ rideId, lat, lng, bearing?, speedKmph? }` |

### server → client
`ride:searching` · `ride:offer` · `ride:offer_revoked` · `ride:driver_assigned` · `ride:assigned` (driver) · `ride:status` · `ride:driver_arrived` · `ride:started` · `ride:driver_location` · `ride:customer_location` · `ride:driver_completed` · `ride:payment_pending` · `ride:payment_update` · `ride:completed` · `ride:cancelled` · `ride:no_drivers` · `notification`

## Ride state machine
`REQUESTED → SEARCHING_DRIVER → DRIVER_ASSIGNED → DRIVER_ARRIVING → DRIVER_ARRIVED → RIDE_STARTED → RIDE_IN_PROGRESS → DRIVER_COMPLETED → PAYMENT_PENDING → COMPLETED`
Branches: `NO_DRIVERS_FOUND`, `PAYMENT_FAILED → (retry) → PAYMENT_PENDING`, `CUSTOMER_CANCELLED`, `DRIVER_CANCELLED`, `SYSTEM_CANCELLED`.
Transitions are validated centrally (`services/rideStateMachine.js`); illegal moves → `409 INVALID_TRANSITION`.
