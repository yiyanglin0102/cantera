/**
 *  @file GasKinetics.cpp Homogeneous kinetics in ideal gases
 */

// This file is part of Cantera. See License.txt in the top-level directory or
// at https://cantera.org/license.txt for license and copyright information.

#include "cantera/kinetics/GasKinetics.h"
#include "cantera/thermo/ThermoPhase.h"

using namespace std;

namespace Cantera
{
GasKinetics::GasKinetics(ThermoPhase* thermo) :
    BulkKinetics(thermo),
    m_logp_ref(0.0),
    m_logc_ref(0.0),
    m_logStandConc(0.0),
    m_pres(0.0)
{
}

void GasKinetics::update_rates_T()
{
    double T = thermo().temperature();
    double P = thermo().pressure();
    m_logStandConc = log(thermo().standardConcentration());
    ArrheniusData arrhenius_shared(T);
    CustomFunc1Data func1_shared(T);
    double logT = arrhenius_shared.m_logT;

    if (T != m_temp) {
        if (!m_rfn.empty()) {
            m_rates.update(T, logT, m_rfn.data());
        }

        if (!m_rfn_low.empty()) {
            m_falloff_low_rates.update(T, logT, m_rfn_low.data());
            m_falloff_high_rates.update(T, logT, m_rfn_high.data());
        }
        if (!falloff_work.empty()) {
            m_falloffn.updateTemp(T, falloff_work.data());
        }
        updateKc();
        m_ROP_ok = false;
    }

    if (T != m_temp || P != m_pres) {

        for (auto& rate : m_arrhenius_rates) {
            // generic reaction rates
            m_rfn.data()[rate.index()] = rate.eval(arrhenius_shared);
        }

        for (auto& rate : m_func1_rates) {
            // generic reaction rates
            m_rfn.data()[rate.index()] = rate.eval(func1_shared);
        }

        if (m_plog_rates.nReactions()) {
            m_plog_rates.update(T, logT, m_rfn.data());
            m_ROP_ok = false;
        }

        if (m_cheb_rates.nReactions()) {
            m_cheb_rates.update(T, logT, m_rfn.data());
            m_ROP_ok = false;
        }
    }
    m_pres = P;
    m_temp = T;
}

void GasKinetics::update_rates_C()
{
    thermo().getActivityConcentrations(m_conc.data());
    doublereal ctot = thermo().molarDensity();

    // 3-body reactions
    if (!concm_3b_values.empty()) {
        m_3b_concm.update(m_conc, ctot, concm_3b_values.data());
    }

    // Falloff reactions
    if (!concm_falloff_values.empty()) {
        m_falloff_concm.update(m_conc, ctot, concm_falloff_values.data());
    }

    // P-log reactions
    if (m_plog_rates.nReactions()) {
        double logP = log(thermo().pressure());
        m_plog_rates.update_C(&logP);
    }

    // Chebyshev reactions
    if (m_cheb_rates.nReactions()) {
        double log10P = log10(thermo().pressure());
        m_cheb_rates.update_C(&log10P);
    }

    m_ROP_ok = false;
}

void GasKinetics::updateKc()
{
    thermo().getStandardChemPotentials(m_grt.data());
    fill(m_rkcn.begin(), m_rkcn.end(), 0.0);

    // compute Delta G^0 for all reversible reactions
    getRevReactionDelta(m_grt.data(), m_rkcn.data());

    doublereal rrt = 1.0 / thermo().RT();
    for (size_t i = 0; i < m_revindex.size(); i++) {
        size_t irxn = m_revindex[i];
        m_rkcn[irxn] = std::min(exp(m_rkcn[irxn]*rrt - m_dn[irxn]*m_logStandConc),
                                BigNumber);
    }

    for (size_t i = 0; i != m_irrev.size(); ++i) {
        m_rkcn[ m_irrev[i] ] = 0.0;
    }
}

void GasKinetics::getEquilibriumConstants(doublereal* kc)
{
    update_rates_T();
    thermo().getStandardChemPotentials(m_grt.data());
    fill(m_rkcn.begin(), m_rkcn.end(), 0.0);

    // compute Delta G^0 for all reactions
    getReactionDelta(m_grt.data(), m_rkcn.data());

    doublereal rrt = 1.0 / thermo().RT();
    for (size_t i = 0; i < nReactions(); i++) {
        kc[i] = exp(-m_rkcn[i]*rrt + m_dn[i]*m_logStandConc);
    }

    // force an update of T-dependent properties, so that m_rkcn will
    // be updated before it is used next.
    m_temp = 0.0;
}

void GasKinetics::processFalloffReactions()
{
    // use m_ropr for temporary storage of reduced pressure
    vector_fp& pr = m_ropr;

    for (size_t i = 0; i < m_falloff_low_rates.nReactions(); i++) {
        pr[i] = concm_falloff_values[i] * m_rfn_low[i] / (m_rfn_high[i] + SmallNumber);
        AssertFinite(pr[i], "GasKinetics::processFalloffReactions",
                     "pr[{}] is not finite.", i);
    }

    m_falloffn.pr_to_falloff(pr.data(), falloff_work.data());

    for (size_t i = 0; i < m_falloff_low_rates.nReactions(); i++) {
        if (reactionTypeStr(m_fallindx[i]) == "falloff") {
            pr[i] *= m_rfn_high[i];
        } else { // CHEMACT_RXN
            pr[i] *= m_rfn_low[i];
        }
        m_ropf[m_fallindx[i]] = pr[i];
    }
}

void GasKinetics::updateROP()
{
    update_rates_C();
    update_rates_T();
    if (m_ROP_ok) {
        return;
    }

    // copy rate coefficients into ropf
    m_ropf = m_rfn;

    // multiply ropf by enhanced 3b conc for all 3b rxns
    if (!concm_3b_values.empty()) {
        m_3b_concm.multiply(m_ropf.data(), concm_3b_values.data());
    }

    if (m_falloff_high_rates.nReactions()) {
        processFalloffReactions();
    }

    for (size_t i = 0; i < nReactions(); i++) {
        // Scale the forward rate coefficient by the perturbation factor
        m_ropf[i] *= m_perturb[i];
        // For reverse rates computed from thermochemistry, multiply the forward
        // rate coefficients by the reciprocals of the equilibrium constants
        m_ropr[i] = m_ropf[i] * m_rkcn[i];
    }

    // multiply ropf by concentration products
    m_reactantStoich.multiply(m_conc.data(), m_ropf.data());

    // for reversible reactions, multiply ropr by concentration products
    m_revProductStoich.multiply(m_conc.data(), m_ropr.data());

    for (size_t j = 0; j != nReactions(); ++j) {
        m_ropnet[j] = m_ropf[j] - m_ropr[j];
    }

    for (size_t i = 0; i < m_rfn.size(); i++) {
        AssertFinite(m_rfn[i], "GasKinetics::updateROP",
                     "m_rfn[{}] is not finite.", i);
        AssertFinite(m_ropf[i], "GasKinetics::updateROP",
                     "m_ropf[{}] is not finite.", i);
        AssertFinite(m_ropr[i], "GasKinetics::updateROP",
                     "m_ropr[{}] is not finite.", i);
    }
    m_ROP_ok = true;
}

void GasKinetics::getFwdRateConstants(doublereal* kfwd)
{
    update_rates_C();
    update_rates_T();

    // copy rate coefficients into ropf
    m_ropf = m_rfn;

    // multiply ropf by enhanced 3b conc for all 3b rxns
    if (!concm_3b_values.empty()) {
        m_3b_concm.multiply(m_ropf.data(), concm_3b_values.data());
    }

    if (m_falloff_high_rates.nReactions()) {
        processFalloffReactions();
    }

    for (size_t i = 0; i < nReactions(); i++) {
        // multiply by perturbation factor
        kfwd[i] = m_ropf[i] * m_perturb[i];
    }
}

bool GasKinetics::addReaction(shared_ptr<Reaction> r)
{
    // operations common to all reaction types
    bool added = BulkKinetics::addReaction(r);
    if (!added) {
        return false;
    }

    shared_ptr<ReactionRateBase> rate=r->reactionRate();
    if (rate) {
        size_t nRxn = nReactions() - 1;

        // new generic reaction type handler
        rate->setIndex(nRxn);
        if (rate->type() == "ArrheniusRate") {
            m_arrhenius_indices[nRxn] = m_arrhenius_rates.size();
            m_arrhenius_rates.push_back(*std::dynamic_pointer_cast<ArrheniusRate>(rate));
        } else if (rate->type() == "custom-function") {
            m_func1_indices[nRxn] = m_func1_rates.size();
            m_func1_rates.push_back(*std::dynamic_pointer_cast<CustomFunc1Rate>(rate));
        } else {
            throw CanteraError("GasKinetics::addReaction", "No longer used.");
        }
    } else if (r->type() == "elementary") {
        addElementaryReaction(dynamic_cast<ElementaryReaction&>(*r));
    } else if (r->type() == "three-body") {
        addThreeBodyReaction(dynamic_cast<ThreeBodyReaction&>(*r));
    } else if (r->type() == "falloff") {
        addFalloffReaction(dynamic_cast<FalloffReaction&>(*r));
    } else if (r->type() == "chemically-activated") {
        addFalloffReaction(dynamic_cast<FalloffReaction&>(*r));
    } else if (r->type() == "pressure-dependent-Arrhenius") {
        addPlogReaction(dynamic_cast<PlogReaction&>(*r));
    } else if (r->type() == "Chebyshev") {
        addChebyshevReaction(dynamic_cast<ChebyshevReaction&>(*r));
    } else {
        throw CanteraError("GasKinetics::addReaction",
            "Unknown reaction type specified: '{}'", r->type());
    }
    return true;
}

void GasKinetics::addFalloffReaction(FalloffReaction& r)
{
    // install high and low rate coeff calculators and extend the high and low
    // rate coeff value vectors
    size_t nfall = m_falloff_high_rates.nReactions();
    m_falloff_high_rates.install(nfall, r.high_rate);
    m_rfn_high.push_back(0.0);
    m_falloff_low_rates.install(nfall, r.low_rate);
    m_rfn_low.push_back(0.0);

    // add this reaction number to the list of falloff reactions
    m_fallindx.push_back(nReactions()-1);
    m_rfallindx[nReactions()-1] = nfall;

    // install the enhanced third-body concentration calculator
    map<size_t, double> efficiencies;
    for (const auto& eff : r.third_body.efficiencies) {
        size_t k = kineticsSpeciesIndex(eff.first);
        if (k != npos) {
            efficiencies[k] = eff.second;
        } else if (!m_skipUndeclaredThirdBodies) {
            throw CanteraError("GasKinetics::addFalloffReaction", "Found "
                "third-body efficiency for undefined species '" + eff.first +
                "' while adding reaction '" + r.equation() + "'");
        }
    }
    m_falloff_concm.install(nfall, efficiencies,
                            r.third_body.default_efficiency);
    concm_falloff_values.resize(m_falloff_concm.workSize());

    // install the falloff function calculator for this reaction
    m_falloffn.install(nfall, r.type(), r.falloff);
    falloff_work.resize(m_falloffn.workSize());
}

void GasKinetics::addThreeBodyReaction(ThreeBodyReaction& r)
{
    m_rates.install(nReactions()-1, r.rate);
    map<size_t, double> efficiencies;
    for (const auto& eff : r.third_body.efficiencies) {
        size_t k = kineticsSpeciesIndex(eff.first);
        if (k != npos) {
            efficiencies[k] = eff.second;
        } else if (!m_skipUndeclaredThirdBodies) {
            throw CanteraError("GasKinetics::addThreeBodyReaction", "Found "
                "third-body efficiency for undefined species '" + eff.first +
                "' while adding reaction '" + r.equation() + "'");
        }
    }
    m_3b_concm.install(nReactions()-1, efficiencies,
                       r.third_body.default_efficiency);
    concm_3b_values.resize(m_3b_concm.workSize());
}

void GasKinetics::addPlogReaction(PlogReaction& r)
{
    m_plog_rates.install(nReactions()-1, r.rate);
}

void GasKinetics::addChebyshevReaction(ChebyshevReaction& r)
{
    m_cheb_rates.install(nReactions()-1, r.rate);
}

void GasKinetics::modifyReaction(size_t i, shared_ptr<Reaction> rNew)
{
    // operations common to all reaction types
    BulkKinetics::modifyReaction(i, rNew);

    shared_ptr<ReactionRateBase> rate=rNew->reactionRate();
    if (rate) {
        // new generic reaction type handler
        if (rate->type() == "ArrheniusRate") {
            modifyArrheniusRate(i, std::dynamic_pointer_cast<ArrheniusRate>(rate));
        } else if (rate->type() == "custom-function") {
            modifyCustomFunc1Rate(i, std::dynamic_pointer_cast<CustomFunc1Rate>(rate));
        } else {
            modifyReactionRate(i, rate);
        }
    } else if (rNew->type() == "elementary") {
        modifyElementaryReaction(i, dynamic_cast<ElementaryReaction&>(*rNew));
    } else if (rNew->type() == "three-body") {
        modifyThreeBodyReaction(i, dynamic_cast<ThreeBodyReaction&>(*rNew));
    } else if (rNew->type() == "falloff") {
        modifyFalloffReaction(i, dynamic_cast<FalloffReaction&>(*rNew));
    } else if (rNew->type() == "chemically-activated") {
        modifyFalloffReaction(i, dynamic_cast<FalloffReaction&>(*rNew));
    } else if (rNew->type() == "pressure-dependent-Arrhenius") {
        modifyPlogReaction(i, dynamic_cast<PlogReaction&>(*rNew));
    } else if (rNew->type() == "Chebyshev") {
        modifyChebyshevReaction(i, dynamic_cast<ChebyshevReaction&>(*rNew));
    } else {
        throw CanteraError("GasKinetics::modifyReaction",
            "Unknown reaction type specified: '{}'", rNew->type());
    }

    // invalidate all cached data
    m_ROP_ok = false;
    m_temp += 0.1234;
    m_pres += 0.1234;
}

void GasKinetics::modifyThreeBodyReaction(size_t i, ThreeBodyReaction& r)
{
    m_rates.replace(i, r.rate);
}

void GasKinetics::modifyFalloffReaction(size_t i, FalloffReaction& r)
{
    size_t iFall = m_rfallindx[i];
    m_falloff_high_rates.replace(iFall, r.high_rate);
    m_falloff_low_rates.replace(iFall, r.low_rate);
    m_falloffn.replace(iFall, r.falloff);
}

void GasKinetics::modifyPlogReaction(size_t i, PlogReaction& r)
{
    m_plog_rates.replace(i, r.rate);
}

void GasKinetics::modifyChebyshevReaction(size_t i, ChebyshevReaction& r)
{
    m_cheb_rates.replace(i, r.rate);
}

void GasKinetics::modifyReactionRate(size_t i, shared_ptr<ReactionRateBase> newRate)
{
    if (m_rxn_indices.find(i) != m_rxn_indices.end()) {

        size_t j = m_rxn_indices[i];
        if (newRate->type() != m_rxn_rates[j]->type()) {
            throw CanteraError("GasKinetics::modifyReactionRate",
                               "Attempting to replace '{}' with '{}'.",
                               m_rxn_rates[j]->type(), newRate->type());
        }
        newRate->setIndex(m_rxn_rates[j]->index());
        m_rxn_rates[j] = newRate;
    } else {
        throw CanteraError("GasKinetics::modifyReactionRate",
                           "Index {} does not exist.", i);
    }
}

void GasKinetics::modifyArrheniusRate(size_t i,
                                      shared_ptr<ArrheniusRate> newRate)
{
    if (m_arrhenius_indices.find(i) != m_arrhenius_indices.end()) {
        size_t j = m_arrhenius_indices[i];
        newRate->setIndex(m_arrhenius_rates[j].index());
        m_arrhenius_rates[j] = *newRate;
    } else {
        throw CanteraError("GasKinetics::modifyArrheniusRate",
                           "Index {} does not exist.", i);
    }
}

void GasKinetics::modifyCustomFunc1Rate(size_t i,
                                        shared_ptr<CustomFunc1Rate> newRate)
{
    if (m_func1_indices.find(i) != m_func1_indices.end()) {
        size_t j = m_func1_indices[i];
        newRate->setIndex(m_func1_rates[j].index());
        m_func1_rates[j] = *newRate;
    } else {
        throw CanteraError("GasKinetics::modifyCustomFunc1Rate",
                           "Index {} does not exist.", i);
    }
}

void GasKinetics::init()
{
    BulkKinetics::init();
    m_logp_ref = log(thermo().refPressure()) - log(GasConstant);
}

void GasKinetics::invalidateCache()
{
    BulkKinetics::invalidateCache();
    m_pres += 0.13579;
}

}
