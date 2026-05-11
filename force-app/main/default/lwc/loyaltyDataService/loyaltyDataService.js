/**
 * @description Shared JS module (wire adapter pattern) providing reactive loyalty data
 *              to all child LWC components. Acts as the single source of truth for
 *              session-level loyalty state — prevents each component from making its own Apex call.
 *
 * USAGE IN CHILD COMPONENTS:
 *   import { getLoyaltyData } from 'c/loyaltyDataService';
 *   // Then call getLoyaltyData(contactId) to get a promise
 *
 * REACTIVE DATA PATTERN:
 *   Components that need reactivity (re-render on data change) should use:
 *     @wire(getSessionLoyaltyData, { contactId: '$recordId' }) wiredData;
 *   This module supplements that by providing a shared in-memory cache and
 *   manual refresh capability across sibling components.
 *
 * CACHE:
 *   - In-memory Map keyed by contactId
 *   - TTL: 30 minutes (matches Platform Cache TTL in LoyaltySessionCacheService)
 *   - Cleared on explicit refresh or page navigation
 */

import getSessionLoyaltyData from '@salesforce/apex/LoyaltyLoginController.getSessionLoyaltyData';
import refreshLoyaltyData    from '@salesforce/apex/LoyaltyLoginController.refreshLoyaltyData';

const CACHE_TTL_MS = 30 * 60 * 1000; // 30 minutes

// Module-level cache shared across all component instances on the same page
const dataCache = new Map();

/**
 * Returns loyalty session data for the given contactId.
 * Uses module-level cache to avoid duplicate Apex calls within TTL.
 *
 * @param {string} contactId - SFSC Contact Id
 * @returns {Promise<MemberSessionData>}
 */
export async function getLoyaltyData(contactId) {
    if (!contactId) return emptySessionData();

    const cached = dataCache.get(contactId);
    if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) {
        return cached.data;
    }

    const data = await getSessionLoyaltyData({ contactId });
    dataCache.set(contactId, { data, fetchedAt: Date.now() });
    return data;
}

/**
 * Forces a cache refresh — bypasses TTL and fetches fresh data from LC.
 * Call this after point adjustments, tier changes, or enrollment events.
 *
 * @param {string} contactId - SFSC Contact Id
 * @returns {Promise<MemberSessionData>}
 */
export async function refreshLoyaltyDataForContact(contactId) {
    dataCache.delete(contactId);
    const data = await refreshLoyaltyData({ contactId });
    dataCache.set(contactId, { data, fetchedAt: Date.now() });
    return data;
}

/**
 * Clears the module-level cache for a specific Contact.
 * Call this on component disconnect or explicit logout.
 */
export function clearLoyaltyCache(contactId) {
    if (contactId) {
        dataCache.delete(contactId);
    } else {
        dataCache.clear();
    }
}

// ── Derived getters (convenience helpers for components) ──────────────────────

export function getTier(data)          { return data?.tier || 'Preferred'; }
export function getPoints(data)        { return data?.pointsBalance ?? 0; }
export function getMemberType(data)    { return data?.memberType || 'Retail'; }
export function getVouchers(data)      { return data?.availableVouchers || []; }
export function isCAMember(data)       { return data?.isCAMember === true; }
export function hasLoyalty(data)       { return data?.hasLoyalty === true; }

// ── Private helpers ───────────────────────────────────────────────────────────

function emptySessionData() {
    return {
        hasLoyalty:        false,
        tier:              null,
        memberType:        null,
        pointsBalance:     0,
        pointsToNextTier:  0,
        nextTierThreshold: 0,
        availableVouchers: [],
        isCAMember:        false,
        lastRefreshed:     null
    };
}
