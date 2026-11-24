"""Company alias table for the 48-ticker universe.

Matching tiers (see ``entities.py``):

* ``strong``     unambiguous names, matched case-insensitively
                 (e.g. "Goldman Sachs", "iPhone").
* ``strong_cs``  unambiguous only when the exact case is kept
                 (e.g. "J&J", "P&G", "Citi").
* ``weak_cs``    common words that are only evidence when something else
                 corroborates them (provider tag, another alias, or an
                 exchange-qualified ticker): "Apple", "Visa", "Oracle".
* ``exclude``    phrases removed from the text *before* matching, to avoid
                 other entities that share a name (e.g. "Merck KGaA").
* ``since``      alias -> first date the alias can refer to the company.

A bare ticker symbol in running text (V, C, MA, GE, BA, KO ...) is never
treated as evidence by itself.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Company:
    ticker: str
    name: str
    strong: tuple[str, ...] = ()
    strong_cs: tuple[str, ...] = ()
    weak_cs: tuple[str, ...] = ()
    exclude: tuple[str, ...] = ()
    since: dict = field(default_factory=dict)


def _c(ticker, name, strong=(), strong_cs=(), weak_cs=(), exclude=(), since=None):
    return Company(ticker, name, tuple(strong), tuple(strong_cs), tuple(weak_cs),
                   tuple(exclude), since or {})


COMPANIES: tuple[Company, ...] = (
    # ---- Technology ---------------------------------------------------
    _c("AAPL", "Apple Inc.", ["Apple Inc", "iPhone", "iPad", "MacBook", "Apple Watch",
                              "AirPods", "Tim Cook"], weak_cs=["Apple"]),
    _c("MSFT", "Microsoft Corporation", ["Microsoft", "Azure", "Satya Nadella", "Xbox"]),
    _c("NVDA", "NVIDIA Corporation", ["Nvidia", "Jensen Huang", "GeForce"]),
    _c("AMD", "Advanced Micro Devices, Inc.", ["Advanced Micro Devices", "Lisa Su", "Radeon",
                                                "Ryzen"], strong_cs=["AMD"]),
    _c("AVGO", "Broadcom Inc.", ["Broadcom", "Hock Tan"]),
    _c("ORCL", "Oracle Corporation", ["Oracle Corp", "Oracle Corporation", "Larry Ellison",
                                      "Safra Catz"], weak_cs=["Oracle"]),
    _c("CSCO", "Cisco Systems, Inc.", ["Cisco"]),
    _c("ADBE", "Adobe Inc.", ["Adobe", "Photoshop"]),
    # ---- Communication Services ----------------------------------------
    _c("GOOGL", "Alphabet Inc. (Google)", ["Alphabet Inc", "Google", "YouTube", "Sundar Pichai",
                                           "Waymo", "DeepMind"], weak_cs=["Alphabet"]),
    _c("META", "Meta Platforms, Inc. (Facebook)", ["Meta Platforms", "Facebook", "Instagram",
                                                   "WhatsApp", "Mark Zuckerberg"],
       weak_cs=["Meta"], since={"Meta Platforms": "2021-10-28", "Meta": "2021-10-28"}),
    _c("NFLX", "Netflix, Inc.", ["Netflix"]),
    _c("DIS", "The Walt Disney Company", ["Disney", "Bob Chapek", "Bob Iger"]),
    _c("CMCSA", "Comcast Corporation", ["Comcast", "NBCUniversal", "Xfinity"]),
    # ---- Consumer Discretionary ----------------------------------------
    _c("AMZN", "Amazon.com, Inc.", ["Amazon.com", "Amazon Web Services", "Jeff Bezos",
                                    "Andy Jassy", "Whole Foods", "Amazon Prime"],
       strong_cs=["AWS"], weak_cs=["Amazon"]),
    _c("TSLA", "Tesla, Inc.", ["Tesla", "Cybertruck", "Gigafactory"], weak_cs=["Elon Musk"]),
    _c("HD", "The Home Depot, Inc.", ["Home Depot"]),
    _c("MCD", "McDonald's Corporation", ["McDonald's", "McDonalds"]),
    _c("NKE", "NIKE, Inc.", ["Nike"]),
    _c("LOW", "Lowe's Companies, Inc.", ["Lowe's", "Lowes Companies"]),
    # ---- Financials ----------------------------------------------------
    _c("JPM", "JPMorgan Chase & Co.", ["JPMorgan", "JP Morgan", "J.P. Morgan", "Jamie Dimon"]),
    _c("BAC", "Bank of America Corporation", ["Bank of America", "BofA", "Merrill Lynch",
                                              "Brian Moynihan"]),
    _c("GS", "The Goldman Sachs Group, Inc.", ["Goldman Sachs"], weak_cs=["Goldman"]),
    _c("V", "Visa Inc.", ["Visa Inc", "Visa Debit", "Visa Credit"], weak_cs=["Visa"]),
    _c("MA", "Mastercard Incorporated", ["Mastercard"]),
    _c("WFC", "Wells Fargo & Company", ["Wells Fargo"]),
    _c("C", "Citigroup Inc.", ["Citigroup", "Citibank"], strong_cs=["Citi"],
       weak_cs=["Jane Fraser"]),
    # ---- Healthcare ----------------------------------------------------
    _c("JNJ", "Johnson & Johnson", ["Johnson & Johnson", "Johnson and Johnson", "Janssen"],
       strong_cs=["J&J"]),
    _c("UNH", "UnitedHealth Group Incorporated", ["UnitedHealth", "United Health Group",
                                                  "UnitedHealthcare", "Optum"]),
    _c("LLY", "Eli Lilly and Company", ["Eli Lilly", "Mounjaro", "Zepbound"], weak_cs=["Lilly"]),
    _c("PFE", "Pfizer Inc.", ["Pfizer", "Paxlovid", "Comirnaty"]),
    _c("ABBV", "AbbVie Inc.", ["AbbVie", "Humira", "Skyrizi", "Rinvoq"]),
    _c("MRK", "Merck & Co., Inc.", ["Merck", "Keytruda", "Gardasil"],
       exclude=["Merck KGaA", "EMD Serono", "EMD Millipore"]),
    # ---- Industrials ---------------------------------------------------
    _c("CAT", "Caterpillar Inc.", ["Caterpillar"]),
    _c("BA", "The Boeing Company", ["Boeing", "737 MAX", "737 Max"]),
    _c("GE", "General Electric Company", ["General Electric", "GE Aerospace", "GE Healthcare",
                                          "GE Vernova", "Larry Culp"], weak_cs=["GE"]),
    _c("HON", "Honeywell International Inc.", ["Honeywell"]),
    _c("UPS", "United Parcel Service, Inc.", ["United Parcel Service"], weak_cs=["UPS"]),
    _c("RTX", "RTX Corporation (Raytheon Technologies)", ["Raytheon", "Pratt & Whitney",
                                                          "Collins Aerospace", "RTX Corp"],
       strong_cs=["RTX"], since={"RTX Corp": "2023-07-17", "RTX": "2023-07-17"}),
    # ---- Consumer Staples ----------------------------------------------
    _c("WMT", "Walmart Inc.", ["Walmart", "Wal-Mart", "Sam's Club"]),
    _c("PG", "The Procter & Gamble Company", ["Procter & Gamble", "Procter and Gamble"],
       strong_cs=["P&G"]),
    _c("KO", "The Coca-Cola Company", ["Coca-Cola", "Coca Cola"], weak_cs=["Coke"]),
    _c("PEP", "PepsiCo, Inc.", ["PepsiCo", "Pepsi", "Frito-Lay"]),
    _c("COST", "Costco Wholesale Corporation", ["Costco"]),
    # ---- Energy --------------------------------------------------------
    _c("XOM", "Exxon Mobil Corporation", ["Exxon"]),
    _c("CVX", "Chevron Corporation", ["Chevron"]),
    _c("COP", "ConocoPhillips", ["ConocoPhillips", "Conoco Phillips"]),
    # ---- Utilities -----------------------------------------------------
    _c("NEE", "NextEra Energy, Inc.", ["NextEra", "Florida Power & Light"], weak_cs=["FPL"]),
    _c("DUK", "Duke Energy Corporation", ["Duke Energy"]),
)

UNIVERSE: dict[str, Company] = {c.ticker: c for c in COMPANIES}
