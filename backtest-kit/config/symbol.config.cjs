const symbolList = [
  {
    icon: "/icon/btc.png",
    logo: "/icon/128/btc.png",
    symbol: "XAUUSD",
    displayName: "Gold Spot",
    color: "#B8860B",
    priority: 10,
    description: [
      "Primary trading symbol for this project.",
      "Backtest source: Dukascopy CSV/CSV.GZ.",
    ].join("\n"),
  },
  {
    icon: "/icon/eth.png",
    logo: "/icon/128/eth.png",
    symbol: "XAGUSD",
    displayName: "Silver Spot",
    color: "#708090",
    priority: 20,
    description: [
      "Secondary symbol used for SMT-style divergence checks.",
      "Used by SINGLE2 port strategy.",
    ].join("\n"),
  },
];

module.exports = symbolList;
