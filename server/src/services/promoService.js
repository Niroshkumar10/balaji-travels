'use strict';

const ApiError = require('../utils/apiError');
const promoRepo = require('../repositories/promoRepo');

const round2 = (n) => Math.round((n + Number.EPSILON) * 100) / 100;

const promoService = {
  /**
   * Validate a code against a fare and return the discount it would apply.
   * Throws a 400/409 with a clear code if the promo can't be used.
   * @returns {Promise<{ promoId:number, code:string, discount:number }>}
   */
  async validate({ code, userId, fare }) {
    const promo = await promoRepo.findByCode(code);
    if (!promo || !promo.is_active) throw ApiError.badRequest('Invalid promo code', 'PROMO_INVALID');

    const now = Date.now();
    if (promo.valid_from && new Date(promo.valid_from).getTime() > now) {
      throw ApiError.badRequest('Promo not active yet', 'PROMO_NOT_STARTED');
    }
    if (promo.valid_to && new Date(promo.valid_to).getTime() < now) {
      throw ApiError.badRequest('Promo has expired', 'PROMO_EXPIRED');
    }
    if (fare < Number(promo.min_fare)) {
      throw ApiError.badRequest(`Minimum fare ₹${promo.min_fare} for this code`, 'PROMO_MIN_FARE');
    }
    if (promo.usage_limit != null && promo.used_count >= promo.usage_limit) {
      throw ApiError.conflict('Promo usage limit reached', 'PROMO_EXHAUSTED');
    }
    const mine = await promoRepo.redemptionsForUser(promo.id, userId);
    if (mine >= promo.per_user_limit) {
      throw ApiError.conflict('You have already used this code', 'PROMO_USER_LIMIT');
    }

    let discount =
      promo.type === 'flat'
        ? Number(promo.value)
        : (fare * Number(promo.value)) / 100;
    if (promo.max_discount != null) discount = Math.min(discount, Number(promo.max_discount));
    discount = round2(Math.max(0, Math.min(discount, fare)));

    return { promoId: promo.id, code: promo.code, discount };
  },

  redeem(ctx, args) {
    return promoRepo.redeem(ctx, args);
  },

  list() {
    return promoRepo.list();
  },
};

module.exports = promoService;
