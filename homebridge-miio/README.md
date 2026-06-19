Homebridge Miio runtime patch
=============================

This directory records the local `homebridge-miio` runtime patch used on
LivingRoom.

Patch summary:

- Keep `miio.device()` failures from continuing into accessory registration with
  an undefined `device` object.
- Hide the token value in the error log only; the runtime config is not changed.

Runtime source:

- `/usr/lib/node_modules/homebridge-miio`
