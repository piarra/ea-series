資金管理モード

モード1では、毎日50000USDを超えた部分のbalanceをRemaining fundsに戻す処理をします。
モード2では、100000USDを超えた場合にそのうちの50000USDを即座にremaining fundsに移動させる処理をします。
モード3では、60000USDを超えた場合に即座に10000USDをremaining fundsに移動させる処理をします。

profit_baseレベル調整モード

--profit-base-level-modeを指定すると、ナンピンlevelが上がるほどprofit_baseを減らします。
減少幅は--profit-base-level-step、下限は--profit-base-level-minで調整できます。

stop_buy_limitのロジックについてはBACKTESTでは実装しない
