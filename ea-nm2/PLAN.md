# NM2 約定力改善プラン

## 目的
バックテストでよい成績なのにリアル口座で勝てない問題を解消する

## 施策

ただしあなたのEAは バスケット（複数ポジ）を平均建値ベースで管理しているので、やるならおすすめはこの形です：

おすすめ：ハイブリッド（発動までは現状、発動後はSLで追う）
	•	トレール“開始判定”（ATR到達 / 固定幅到達 / deep-profit到達）は今のまま
	•	いったん開始したら、以後の“戻り判定”で CloseBasket() する代わりに
全ポジのSLを stop_price に寄せていく（サーバー側で刈らせる）

これでリアルで起きがちな「ティック遅延→成行が滑る」「ヒゲで判定→成行が悪約定」をかなり減らせます。

⸻

Titan/Exness前提での注意点（ここだけ押さえれば事故りにくい）

1) StopLevel / FreezeLevel を毎回チェック

銘柄・時間帯で変わることがあるので、SL更新前に
	•	SYMBOL_TRADE_STOPS_LEVEL
	•	SYMBOL_TRADE_FREEZE_LEVEL
を見て、現在価格から近すぎるSLは通さない（または少し離す）。

2) バスケットの“平均建値ロック”をSLでも再現する

あなたの実装には「L3+で建値付近ロック」思想がありますよね。
SL化でも同じで、stop_price を
	•	BUY: max(stop_price, buy.avg_price + lock_distance)
	•	SELL: min(stop_price, sell.avg_price - lock_distance)
で下限/上限を作るのが大事です。

⸻

実装イメージ（MQL5・最小構成）

あなたの ManageBuyTakeProfit / ManageSellTakeProfit の「trail hit で CloseBasket」部分を **“SL更新”**に置き換えます。

1) stop_price を計算するのは今のまま

既にここがあるので、その stop_price を使います。

2) バスケット内の全ポジに SL を当てる

（TPは付けなくてOK。TP付けると挙動が複雑になることが多い）

bool UpdateBasketSL(const SymbolState &state, ENUM_POSITION_TYPE type, double new_sl)
{
  const string symbol = state.broker_symbol;
  const int magic = state.params.magic_number;

  int stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
  int freeze_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
  double point = state.point; if(point<=0) point=0.00001;

  MqlTick t; if(!SymbolInfoTick(symbol, t)) return false;
  double bid=t.bid, ask=t.ask;

  // SLが近すぎるとModifyが通らないので最低距離を確保
  double min_dist = (stops_level + freeze_level + 2) * point;

  // typeごとに価格から見て妥当な位置へクランプ
  if(type == POSITION_TYPE_BUY)
  {
    double max_sl = bid - min_dist;
    if(new_sl > max_sl) new_sl = max_sl;
  }
  else
  {
    double min_sl = ask + min_dist;
    if(new_sl < min_sl) new_sl = min_sl;
  }

  CTrade tr;
  tr.SetExpertMagicNumber(magic);
  tr.SetDeviationInPoints(state.params.slippage_points);
  int filling = state.filling_mode;
  if(filling==ORDER_FILLING_FOK||filling==ORDER_FILLING_IOC||filling==ORDER_FILLING_RETURN)
    tr.SetTypeFilling((ENUM_ORDER_TYPE_FILLING)filling);

  bool any=false;

  for(int i=PositionsTotal()-1;i>=0;--i)
  {
    ulong ticket = PositionGetTicket(i);
    if(!PositionSelectByTicket(ticket)) continue;
    if((int)PositionGetInteger(POSITION_MAGIC) != magic) continue;
    if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
    if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != type) continue;

    double cur_sl = PositionGetDouble(POSITION_SL);
    double tp     = PositionGetDouble(POSITION_TP);

    // 「改善方向」のSLだけ更新（BUYならSLを上げる、SELLならSLを下げる）
    if(type==POSITION_TYPE_BUY)
    {
      if(cur_sl > 0 && new_sl <= cur_sl + point*0.5) continue;
    }
    else
    {
      if(cur_sl > 0 && new_sl >= cur_sl - point*0.5) continue;
    }

    // PositionModifyはsymbol指定（ヘッジ口座でもsymbol単位で通る）
    if(tr.PositionModify(symbol, new_sl, tp))
      any=true;
  }
  return any;
}

3) “トレールヒット”判定を消す（または保険として残す）

本来は「SLが刺さる」ので CloseBasket() を呼ばなくてよいです。
ただし保険で、
	•	SL更新が何回も失敗した
	•	価格が既に抜けた（判定遅れ）
みたいな時だけ CloseBasket() を使う、という二段構えが安定します。

⸻

パラメータ面での調整（SL化すると効き方が変わる）

SLトレールにすると「トレールが実弾」になるので、
	•	TrailingTakeProfitDistanceRatio は 現状より少し広めが安全（0.45→0.55〜0.65）
	•	EnableTakeProfitTrailDistanceCap は まずOFFで挙動確認がおすすめ
（キャップが効くとSLがタイトになりすぎて“ちょい戻り刈り”が増えることがある）

⸻

まずの優先順位（Titan/Exnessで勝ちやすくする順）
	1.	TPトレール発動後はSL更新方式（今回の話）
	2.	できれば EnableHedgedEntry=false（SL方式と相性が良い）
	3.	SL更新に StopLevel/FreezeLevel ガード＋リトライ＋失敗時フォールバックClose を入れる

⸻

もし次に教えてもらえるなら、かなり精密に詰められます：
	•	口座タイプ：Hedge口座でOK？（Titan/Exnessでも口座タイプ選べることが多い）
	•	「リアルで増えてる損切り」がどれか：Absolute basket stop / Final level stop / Timed exit

それが分かると、SL化の効果が最大化する箇所（深いレベルロックの入れ方、トレール開始条件の最適化）まで一気に設計できます。
