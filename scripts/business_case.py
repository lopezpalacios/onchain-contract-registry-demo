#!/usr/bin/env python3
"""Illustrative business-case model for the smart contract registry.

All inputs are assumptions. Replace them with the bank's actual loaded costs,
audit fees, incident scenarios and revenue attribution before using this in a
committee paper.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass


@dataclass
class Case:
    name: str
    build_cost: float
    annual_run: float
    audit_reuse: float
    deployment_productivity: float
    manual_registry_effort: float
    regulatory_efficiency: float
    risk_adjusted_incident: float
    attributed_revenue: float

    @property
    def annual_benefit(self) -> float:
        return (
            self.audit_reuse
            + self.deployment_productivity
            + self.manual_registry_effort
            + self.regulatory_efficiency
            + self.risk_adjusted_incident
            + self.attributed_revenue
        )

    @property
    def annual_net(self) -> float:
        return self.annual_benefit - self.annual_run

    def npv(self, discount_rate: float, years: int) -> float:
        value = -self.build_cost
        for year in range(1, years + 1):
            value += self.annual_net / ((1 + discount_rate) ** year)
        return value

    def payback_years(self) -> float | None:
        if self.annual_net <= 0:
            return None
        return self.build_cost / self.annual_net

    def roi(self, years: int) -> float:
        total_cost = self.build_cost + self.annual_run * years
        total_benefit = self.annual_benefit * years
        return (total_benefit - total_cost) / total_cost

    def summary(self, discount_rate: float, years: int) -> dict:
        data = asdict(self)
        data.update({
            "annual_benefit": round(self.annual_benefit),
            "annual_net": round(self.annual_net),
            "payback_years": round(self.payback_years(), 2) if self.payback_years() else None,
            "npv": round(self.npv(discount_rate, years)),
            "roi_percent": round(self.roi(years) * 100, 1),
            "years": years,
            "discount_rate": discount_rate,
        })
        return data


SCENARIOS = {
    "efficiency": Case(
        name="Efficiency only",
        build_cost=1_400_000,
        annual_run=380_000,
        audit_reuse=150_000,
        deployment_productivity=100_000,
        manual_registry_effort=150_000,
        regulatory_efficiency=50_000,
        risk_adjusted_incident=0,
        attributed_revenue=0,
    ),
    "pilot": Case(
        name="One-product control pilot",
        build_cost=350_000,
        annual_run=150_000,
        audit_reuse=80_000,
        deployment_productivity=40_000,
        manual_registry_effort=0,
        regulatory_efficiency=60_000,
        risk_adjusted_incident=100_000,
        attributed_revenue=0,
    ),
    "base": Case(
        name="Base (efficiency + risk + attributed revenue)",
        build_cost=1_400_000,
        annual_run=380_000,
        audit_reuse=180_000,
        deployment_productivity=120_000,
        manual_registry_effort=160_000,
        regulatory_efficiency=100_000,
        risk_adjusted_incident=150_000,
        attributed_revenue=200_000,
    ),
    "upside": Case(
        name="Upside (scale + faster launches)",
        build_cost=1_400_000,
        annual_run=450_000,
        audit_reuse=220_000,
        deployment_productivity=180_000,
        manual_registry_effort=200_000,
        regulatory_efficiency=150_000,
        risk_adjusted_incident=300_000,
        attributed_revenue=500_000,
    ),
}


def print_table(discount_rate: float, years: int) -> None:
    header = f"{'Scenario':22} {'Benefit':>10} {'Run':>10} {'Net':>10} {'Payback':>9} {'NPV':>12} {'ROI':>7}"
    print(header)
    print("-" * len(header))
    for key in ("pilot", "efficiency", "base", "upside"):
        case = SCENARIOS[key]
        payback = case.payback_years()
        print(
            f"{case.name[:22]:22} {case.annual_benefit:>10,.0f} {case.annual_run:>10,.0f} "
            f"{case.annual_net:>10,.0f} {(f'{payback:.1f}y' if payback else 'n/a'):>9} "
            f"{case.npv(discount_rate, years):>12,.0f} {case.roi(years) * 100:>6.1f}%"
        )
    print()
    print(f"Build cost: pilot {SCENARIOS['pilot'].build_cost:,.0f}; scale cases {SCENARIOS['base'].build_cost:,.0f}; discount rate {discount_rate:.0%}; horizon {years} years.")
    print("Figures are illustrative and not a forecast.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--discount-rate", type=float, default=0.10)
    parser.add_argument("--years", type=int, default=5)
    parser.add_argument("--scenario", choices=["pilot", "efficiency", "base", "upside", "all"], default="all")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    if args.scenario == "all":
        if args.json:
            print(json.dumps({key: SCENARIOS[key].summary(args.discount_rate, args.years) for key in SCENARIOS}, indent=2))
        else:
            print_table(args.discount_rate, args.years)
    else:
        print(json.dumps(SCENARIOS[args.scenario].summary(args.discount_rate, args.years), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
