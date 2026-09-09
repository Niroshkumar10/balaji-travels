'use strict';

const { Router } = require('express');
const authRoutes = require('./auth.routes');
const customerRoutes = require('./customers.routes');
const driverRoutes = require('./drivers.routes');
const rideRoutes = require('./rides.routes');
const misc = require('./misc.routes');
const opsRoutes = require('./ops.routes');

const router = Router();

router.use('/auth', authRoutes);
router.use('/customers', customerRoutes);
router.use('/drivers', driverRoutes);
router.use('/rides', rideRoutes);

router.use('/fare', misc.fare);
router.use('/places', misc.places);
router.use('/payments', misc.payments);
router.use('/ratings', misc.ratings);
router.use('/earnings', misc.earnings);
router.use('/promos', misc.promos);
router.use('/notifications', misc.notifications);

router.use('/ops', opsRoutes);

module.exports = router;
