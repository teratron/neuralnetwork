//+------------------------------------------------------------------+
//|                                                         NNMA.mq4 |
//|                                     Copyright © 2020, Metaquotes |
//+------------------------------------------------------------------+
#property copyright   "Copyright © 2020, Metaquotes"
#property link        "http://www.metaquotes.ru"
#property description "description 1"
#property description "description 2"
#property description "description 3"
#property version     "1.07"
#property strict

#define   MAGIC            888
#define   MODE_IDENTITY    0	// Identity (тождественная)
#define   MODE_SIGMOID     1	// Logistic, a.k.a. sigmoid or soft step (логистическая, сигмоида или гладкая ступенька)
#define   MODE_TANH        2	// TanH - hyperbolic (гиперболический тангенс)
#define   MODE_RELU        3	// ReLu - rectified linear unit (линейный выпрямитель)
#define   MODE_LEAKYRELU   4	// Leaky ReLu - leaky rectified linear unit (линейный выпрямитель с «утечкой»)

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
input  ENUM_TIMEFRAMES TimeFrame = PERIOD_H1;

// Параметры торговли
//-----------------------------------------
input  double TakeProfit     = 1000;   // TakeProfit (пункты)
input  double StopLoss       = 300;    // StopLoss (пункты) или минимально возможный StopLoss, если считается динамически
input  double TrailingStop   = 100;    // TrailingStop (пункты), если 0, то отключен
input  int    NumOrder       = 0;      // NumOrder - количество ордеров, если 0, то торговля выключена
input  int    Shift          = 1;      // Shift - бар на котором считается сигнал

// Параметры модуля расчёта лота
//-----------------------------------------
input  double LotsDepoOne    = 0.0;    // Размер депозита для одного минилота и по достижению которого начинается увеличения лота, 0 - фиксированный лот

// Параметры расчёта истории баланса
//-----------------------------------------
input  datetime StartTimeBalance = D'2021.01.01';

// Параметры Moving Average {1, 5, 9}
//-----------------------------------------
int MAPeriod[] = {5};      // Перечень периодов MA
int MAMethode  = 0;              // Метод MA (0...3)
int MAPrice    = 0;              // Цена MA (0...6)

// Параметры ATR {1, 5, 9}
//-----------------------------------------
int ATRPeriod[] = {0};     // ATRPeriod - Период ATR, если {0}, то отключен

// Параметры Neural Network
//-----------------------------------------
int    NNLayerNum  = 4;          // NumLayer - количество нейронных слоёв (Input + Hidden... + Output)
int    NNInputBar  = 20;         // NNInputBar
int    NNOutputBar = 1;          // NNOutputBar
int    NNMode      = MODE_TANH;  // NNMode - идентификатор функции активации
double NNBias      = 1;          // NNBias - нейронное смещение, если 0, то отключено
double NNScale     = 100;        // NNScale - коэфициент масштабирования данных, приводящих к промежутку от -1 до 1

// L - количество слоёв в нейросети NNLayerNum
// N - макс. число нейронов, которое присутствует в одном из слоёв матрицы, включая NNInputBar*(ArraySize(MAPeriod)) и NNOutputBar
//                  L-1  N+1  N
int    NNRange[] = {3,   21,  20};
double NNWeight[    3,   21,  20];  // Веса
bool   IsExistWeight = false;

// Нейронные узлы
//              L  N+1
double NNNeuron[4, 21];

//+------------------------------------------------------------------+
//| Parameters                                                       |
//+------------------------------------------------------------------+
datetime BarTimer;
string   Label, Path;
string   FileName, PeriodName;
string   PreObjNameInd;
string   PreObjNameArrow;
string   Title        = "NNMA";
string   Prefix       = "nnma_";
string   ObjNameInd   = "ind_";
string   ObjNameArrow = "arrow_";
double   TP, SL, TS;
double   Points, Balance;
double   Lots, LotsMax, LotsMin;
double   ProfitBuy, ProfitSell;
int      MaxSpread = 20;    // Макс. спред для торговли
int      Attempts  = 10;    // Количество попыток
int      Slippage  = 20;
int      Digit, Magic;
int      NNInputNum;

// Arrays
//-----------------------------------------
double  ArrayBalance[24,7];

//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
//---
    // Удаляем эксперт при не совпадении условий
    //-----------------------------------------
    if (IsOptimization() && CheckNormalCondition()) ExpertRemove();
//---
    Digit   = (int)MarketInfo(NULL, MODE_DIGITS);
    Points  = MarketInfo(NULL, MODE_POINT);
    LotsMax = MarketInfo(NULL, MODE_MAXLOT);
    LotsMin = MarketInfo(NULL, MODE_MINLOT);
//---
    SL = StopLoss*Points;
    TP = TakeProfit*Points;
    TS = TrailingStop*Points;
    BarTimer        = 0;
    NNInputNum      = NNInputBar*(ArraySize(MAPeriod));
    PreObjNameInd   = Prefix + ObjNameInd;
    PreObjNameArrow = Prefix + ObjNameArrow;
//---
    // Magic эксперта
    //-----------------------------------------
    Magic = MAGIC + TimeFrame*64;
//---
    // Проверка состояния для нормальной работы эксперта
    //-----------------------------------------
    if (!IsTesting() || IsVisualMode()) {
        if (Magic > 2147483646 || TakeProfit < StopLoss || TakeProfit <= TrailingStop)
            Alert("Условия не соответствуют нормальной работе эксперта");

        // Торговый лот
        Lots = GetSizeLot();
    }
//---
    // Текст комментария ордера
    //-----------------------------------------
    Label = Title + " #" + (string)Magic;
//---
    // Пути файла
    //-----------------------------------------
    FolderCreate(Title);
    Path = Title + "\\";
//---
    // Название файла
    //-----------------------------------------
    int i;
    int j = ArraySize(MAPeriod);
    int k = j - 1;
    PeriodName = "";
    for (i=0; i < j; i++) {
        PeriodName += IntegerToString(MAPeriod[i]);
        if (i < k) PeriodName += "-";
    }
    PeriodName += "_";
    if (ATRPeriod[0] == 0) {
        PeriodName += "0";
    } else {
        j = ArraySize(ATRPeriod);
        NNInputNum += NNInputBar*j;
        k = j - 1;
        for (i=0; i < j; i++) {
            PeriodName += IntegerToString(ATRPeriod[i]);
            if (i < k) PeriodName += "-";
        }
    }
    FileName = Path + Prefix + Symbol() + "_M" + (string)TimeFrame + "_" + PeriodName + ".dat";
//---
    // Записываем в файл превышения MA и ATR
    //-----------------------------------------
    WriteDelta(TimeFrame, FileName);
//---
    // Читаем из файл обученные веса нейросети
    //-----------------------------------------
    ReadWeight(FileName, NNRange[0], NNRange[1], NNRange[2]);
//---
    // Для работы с экспертом на выходных
    //-----------------------------------------
    if (!IsTesting())
        if (DayOfWeek() == 5 || DayOfWeek() == 1) OnTick();
//---
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
//---
    if (!IsTesting()) {
        ObjectsDeleteAll(0, Prefix, EMPTY);
        WriteStatistic();
        Comment("");
    }
//---
   return;
}
//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
void OnTick() {
//---
    int i, j;
    int signal = 0;
    int signal_open  = 0;
    int signal_close = 0;
    double a, b;
    //string name;
//---
    // Счётчик открытых позиций
    //-----------------------------------------
    datetime timer_buy  = 0;
    datetime timer_sell = 0;
    int order_sell = 0;
    int order_buy  = 0;
    ProfitSell = 0.0;
    ProfitBuy  = 0.0;
//---
    for (i=0; i<OrdersTotal(); i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderMagicNumber() == Magic && OrderSymbol() == Symbol()) {
            if (OrderType() == OP_BUY) {
                if (timer_buy < OrderOpenTime()) timer_buy = OrderOpenTime();
                ProfitBuy += OrderProfit();
                order_buy++;
            }
            if (OrderType() == OP_SELL) {
                if (timer_sell < OrderOpenTime()) timer_sell = OrderOpenTime();
                ProfitSell += OrderProfit();
                order_sell++;
            }
        }
    }
//---
    if (timer_buy == 0 || timer_sell == 0) {
        for (i=0; i<OrdersHistoryTotal(); i++) {
            if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderMagicNumber() == Magic && OrderSymbol() == Symbol()) {
                if (OrderType() == OP_BUY  && timer_buy  < OrderOpenTime()) timer_buy  = OrderOpenTime();
                if (OrderType() == OP_SELL && timer_sell < OrderOpenTime()) timer_sell = OrderOpenTime();
            }
        }
    }
//---
    // Вход на новой свече
    //--------------------------------------------
    if (iBarShift(NULL, TimeFrame, BarTimer) > 0) {
        if (Shift > 0) {
            if (IsExistWeight) {
                for (i = Shift; i < Shift + 100; i++) {
                    j = GetInput(TimeFrame, i);
                    j = GetOutput(NNRange[0], NNRange[1], NNRange[2], NNMode);
                    if (!IsTesting() || IsVisualMode()) DrawOutput(TimeFrame, NNRange[0], NNRange[2], i);
                }
            }
            /*for (i = 0, a = 0.0; i < NNRange[2] && NNNeuron[NNRange[0],i] != EMPTY_VALUE; i++) {
                //Print(NNNeuron[NNRange[0],i]);
                a += NNNeuron[NNRange[0],i] / NNScale;
            }
            Print(a/Points);*/
 
            // Сигнал на открытие и закрытие
            //signal = GetSignal(TimeFrame, P[LEVEL_UPPER,0], P[LEVEL_LOWER,0], Shift);
            //signal_open = signal;//GetSignalOpen(TimeFrame, NumOrder, signal, Shift_2);
        }
        BarTimer = TimeCurrent();
    } else {
        if (Shift == 0) {
            // Сигнал на открытие и закрытие
            //signal = GetSignal(TimeFrame, P0[LEVEL_UPPER], P0[LEVEL_LOWER], 0);
            //signal_open = signal;
        }
    }
//---
    // Закрытие
    if (order_sell > 0 && signal > 0) order_sell = CloseOrder(OP_SELL);
    if (order_buy  > 0 && signal < 0) order_buy  = CloseOrder(OP_BUY);
//---
    // Открытие
    if (signal_open != 0 && TimeAllowed() && MarketInfo(NULL, MODE_SPREAD) <= MaxSpread) {
        a = MarketInfo(NULL, MODE_ASK);
        b = MarketInfo(NULL, MODE_BID);
        Lots = GetSizeLot();
        if (signal_open > 0 && order_buy  < NumOrder && iBarShift(NULL, TimeFrame, timer_buy)  > 0) i = OpenOrder(OP_BUY,  Lots, a, a-SL, a+TP, Label, 0);
        if (signal_open < 0 && order_sell < NumOrder && iBarShift(NULL, TimeFrame, timer_sell) > 0) i = OpenOrder(OP_SELL, Lots, b, b+SL, b-TP, Label, 0);
    }
//---
    // TrailingStop
    //--------------------------------------------
    if (TrailingStop > 0.0)
        if (order_buy > 0 || order_sell > 0) TrailingOrder();
//---
    // Вывод информации
    //--------------------------------------------
    if (!IsTesting() || IsVisualMode()) {
        Balance = GetHistoryBalance(); // Считаем баланс для текущего эксперта
        SetComment(GetLastError());
    }
//---
}
//+------------------------------------------------------------------+
//| Входные данные                                                   |
//+------------------------------------------------------------------+
int GetInput(int timeframe, int shift) {
//---
    int i, j, k = 0;
    double a, b;
//---
    ArrayInitialize(NNNeuron, EMPTY_VALUE);
//---
    for (i = shift; i < shift + NNInputBar; i++) { // по барам
        for (j = 0; j < ArraySize(MAPeriod); j++) { // по периодам
            a = iMA(NULL, timeframe, MAPeriod[j], 0, MAMethode, MAPrice, i);
            b = iMA(NULL, timeframe, MAPeriod[j], 0, MAMethode, MAPrice, i + 1);
            NNNeuron[0,k] = NormalizeDouble(a - b, Digit) * NNScale;
            if (!IsTesting() || IsVisualMode()) DrawLine(timeframe, PreObjNameInd + IntegerToString(k), i, a, i + 1, b, false, STYLE_SOLID, 2, clrDodgerBlue);
            k++;
        }
        if (ATRPeriod[0] > 0) {
            for (j = 0; j < ArraySize(ATRPeriod); j++) { // по периодам
                a = iATR(NULL, timeframe, ATRPeriod[j], i);
                b = iATR(NULL, timeframe, ATRPeriod[j], i + 1);
                NNNeuron[0,k] = NormalizeDouble(a - b, Digit) * NNScale;
                k++;
            }
        }
    }
    if (k == NNInputNum) NNNeuron[0,k] = NNBias;
//---
    return(k);
}
//+------------------------------------------------------------------+
//| Идеальные данные                                                 |
//+------------------------------------------------------------------+
int GetOutput(int r1, int r2, int r3, int mode) {
//---
    int i, j, k;
    double sum;
//---
    for (i = 0; i < r1; i++) { // по слоям
        for (k = 0; k < r3 && NNWeight[i,0,k] != EMPTY_VALUE; k++) {  // по следующему нейронному слою
            for (j = 0, sum = 0.0; j < r2 && NNWeight[i,j,k] != EMPTY_VALUE; j++) {  // по предыдущему нейронному слою
                if (NNNeuron[i,j] == EMPTY_VALUE && i > 0) NNNeuron[i,j] = NNBias;
                sum += NNNeuron[i,j] * NNWeight[i,j,k];
            }
            NNNeuron[i+1,k] = GetActivation(sum, mode);
        }
    }
//---
    return(i);
}
//+------------------------------------------------------------------+
//| Activation function                                              |
//+------------------------------------------------------------------+
double GetActivation(double value, int mode) {
//---
	switch (mode) {
    	default:
    	case MODE_IDENTITY:
    		return(value);
    	case MODE_SIGMOID:
    		return(1 / (1 +  MathExp(-value)));
    	case MODE_TANH:
    		value = MathExp(2 * value);
    		return((value - 1) / (value + 1));
    	case MODE_RELU:
    		if (value < 0) return(0);
    		return(value);
    	case MODE_LEAKYRELU:
    		if (value < 0) return(.01 * value);
    		return(value);
	}
//---
}
//+------------------------------------------------------------------+
//| Рисуем выходные данные                                           |
//+------------------------------------------------------------------+
void DrawOutput(int timeframe, int r1, int r3, int shift) {
//---
    double a = iMA(NULL, timeframe, MAPeriod[0], 0, MAMethode, MAPrice, shift);
//---
    for (int i = 0; i < r3 && NNNeuron[r1,i] != EMPTY_VALUE; i++) {
        double c = NNNeuron[r1,i] / NNScale;
        if (!IsOptimization()) Print(NormalizeDouble(c, Digit));
        double b = a + c;
        DrawLine(timeframe, PreObjNameInd + IntegerToString(iBars(NULL, timeframe) - shift) + "_" + IntegerToString(i) + "_output", shift - i, a, shift - i - 1, b, false, STYLE_SOLID, 2, clrOrangeRed);
        a = b;
    }
//---
}
//+------------------------------------------------------------------+
//| Читаем из файл обученные веса нейросети                          |
//+------------------------------------------------------------------+
void ReadWeight(string filename, int r1, int r2, int r3) {
//---
    int i, j, k, n;
    string str, result[];
    filename += ".weight";
//---
    ArrayInitialize(NNWeight, EMPTY_VALUE);
//---
    if (FileIsExist(filename)) {
        int filehandle = FileOpen(filename, FILE_READ|FILE_CSV, "\n");
        if (filehandle != INVALID_HANDLE) {
            i = 0;
            while (!FileIsEnding(filehandle) && i < r1) { // по слоям
                j = 0;
                while (!FileIsEnding(filehandle) && j <= r2) {
                    str = StringTrimRight(FileReadString(filehandle));
                    if (str == "") break;
                    n = StringSplit(str, '\t', result);
                    for (k = 0; k < n && n <= r3; k++) NNWeight[i,j,k] = StringToDouble(result[k]);
                    j++;
                }
                i++;
            }
            if (!IsOptimization()) Print("Файл считан");
            IsExistWeight = true;
        }
        FileClose(filehandle);
    }
//---
}
//+------------------------------------------------------------------+
//| Записываем в файл превышения MA и ATR                            |
//+------------------------------------------------------------------+
void WriteDelta(int timeframe, string filename) {
//---
    int i, j, k, p;
    int numMA  = ArraySize(MAPeriod);
    int numATR = ArraySize(ATRPeriod);
    int lstMA  = numMA  - 1;
    int lstATR = numATR - 1;
    string row, str;
    double a, b;
    double maxMA  = 0.0;
    double maxATR = 0.0;
//---
    if (!FileIsExist(filename)) {
        int filehandle = FileOpen(filename, FILE_CSV|FILE_WRITE, "\t");
        //for (i = iBars(NULL, timeframe) - MathMax(MAPeriod[lstMA], ATRPeriod[lstATR]) - 1, k = 0; i > 0; i--, k++) {
        for (i = 10000, k = 0; i > 0; i--, k++) {
            row = "";
            for (j = 0; j < numMA; j++) {
                a = NormalizeDouble((iMA(NULL, timeframe, MAPeriod[j], 0, MAMethode, MAPrice, i) - iMA(NULL, timeframe, MAPeriod[j], 0, MAMethode, MAPrice, i+1)) / Points, 0);
                maxMA = MathMax(maxMA, a);
                if (a != 0.0 && a < 1000) {
                    b = MathMod(a, 10);
                    if (MathAbs(b) < 5) a -= b;
                    else
                        if (a > 0.0) a += 10 - b;
                        else a -= 10 + b;
                } else {
                    if (a > 1000) a = 1000;
                }
                p = (int)a;
                if (p == 0) str = "0"; else str = (string)p;
                row += str;
                if (j < lstMA) row += "\t";
            }
            if (ATRPeriod[0] > 0) {
                row += "\t";
                for (j = 0; j < numATR; j++) {
                    a = NormalizeDouble((iATR(NULL, timeframe, ATRPeriod[j], i) - iATR(NULL, timeframe, ATRPeriod[j], i+1)) / Points, 0);
                    maxATR = MathMax(maxATR, a);
                    if (a != 0.0 && a < 1000) {
                        b = MathMod(a, 10);
                        if (MathAbs(b) < 5) a -= b;
                        else
                            if (a > 0.0) a += 10 - b;
                            else a -= 10 + b;
                    } else {
                        if (a > 1000) a = 1000;
                    }
                    p = (int)a;
                    if (p == 0) str = "0"; else str = (string)p;
                    row += str;
                    if (j < lstATR) row += "\t";
                }
            }
            FileWrite(filehandle, row);
        }
        if (!IsOptimization()) Print("Файл записан. ", k," строк");
        FileClose(filehandle);
        Print("DataScale MA/ATR: ", maxMA, " / ", maxATR);
    }
//---
}
//+------------------------------------------------------------------+
//| Рисуем линию                                                     |
//+------------------------------------------------------------------+
void DrawLine(int timeframe, string name, int bar_1, double price_1, int bar_2, double price_2, bool ray, int style, int width, color clr) {
//---
    datetime t1, t2;
    if (bar_1 >= 0) t1 = iTime(NULL, timeframe, bar_1); else t1 = iTime(NULL, timeframe, 0) + MathAbs(bar_1)*timeframe*60;
    if (bar_2 >= 0) t2 = iTime(NULL, timeframe, bar_2); else t2 = iTime(NULL, timeframe, 0) + MathAbs(bar_2)*timeframe*60;
//---
    if (ObjectFind(name) < 0) {
        ObjectCreate(name, OBJ_TREND, 0,  t1, price_1, t2, price_2);
        ObjectSet   (name, OBJPROP_RAY,   ray);
        ObjectSet   (name, OBJPROP_STYLE, style);
        ObjectSet   (name, OBJPROP_WIDTH, width);
        ObjectSet   (name, OBJPROP_COLOR, clr);
    } else {
        ObjectMove(name, 0, t1, price_1);
        ObjectMove(name, 1, t2, price_2);
        ObjectSet (name, OBJPROP_COLOR, clr);
    }
//---
}
//+------------------------------------------------------------------+
//| Рисуем стрелку                                                   |
//+------------------------------------------------------------------+
void DrawArrow(int timeframe, string name, int type, int bar, double price, int width, color clr) {
//---
    if (ObjectFind(name) < 0) {
        ObjectCreate(name, type, 0, iTime(NULL, timeframe, bar), price);
        ObjectSet   (name, OBJPROP_WIDTH, width);
        ObjectSet   (name, OBJPROP_COLOR, clr);
        if (type == OBJ_ARROW_DOWN) ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
    } else {
        ObjectMove(name, 0, iTime(NULL, timeframe, bar), price);
        ObjectSet (name, OBJPROP_COLOR, clr);
    }
//---
}
//+------------------------------------------------------------------+
//| Открытие ордера                                                  |
//+------------------------------------------------------------------+
int OpenOrder(int type, double lots, double price, double sl, double tp, string label, datetime xp) {
//---
    int ticket, k = 0;
//---
    while (true) {
        ticket = -1;
        switch (type) {
            case OP_BUY      : ticket = OrderSend(Symbol(), type, lots, price, Slippage, sl, tp, label, Magic,  0, clrBlue);      break;
            case OP_SELL     : ticket = OrderSend(Symbol(), type, lots, price, Slippage, sl, tp, label, Magic,  0, clrRed);       break;
            case OP_BUYSTOP  : ticket = OrderSend(Symbol(), type, lots, price, Slippage, sl, tp, label, Magic, xp, clrRoyalBlue); break;
            case OP_SELLSTOP : ticket = OrderSend(Symbol(), type, lots, price, Slippage, sl, tp, label, Magic, xp, clrTomato);    break;
            case OP_BUYLIMIT : ticket = OrderSend(Symbol(), type, lots, price, Slippage, sl, tp, label, Magic, xp, clrRoyalBlue); break;
            case OP_SELLLIMIT: ticket = OrderSend(Symbol(), type, lots, price, Slippage, sl, tp, label, Magic, xp, clrTomato);    break;
            default          : return(ticket);
        }
        if (ticket < 0) {
            k++;
            if (k >= Attempts) {
                if (!IsTesting()) Print("Не удалось открыть/отложить ордер");
                Sleep(5000);
                return(ticket);
            }
            Sleep(1000);
            RefreshRates();
        } else return(ticket);
    }
//---
    return(-1);
}
//+------------------------------------------------------------------+
//| Закрытие ордеров                                                 |
//+------------------------------------------------------------------+
int CloseOrder(int type) {
//---
    string text = "закрыть";
    bool   check;
    int    i, j, k;
//---
    for (i=OrdersTotal()-1, j=0; i>=0; i--) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderMagicNumber() == Magic && OrderSymbol() == Symbol() && OrderType() == type) {
            j++;
            k = 0;
            while (true) {
                switch (type) {
                    case OP_BUY      : check = OrderClose(OrderTicket(), OrderLots(), MarketInfo(NULL, MODE_BID), Slippage, clrViolet); break;
                    case OP_SELL     : check = OrderClose(OrderTicket(), OrderLots(), MarketInfo(NULL, MODE_ASK), Slippage, clrViolet); break;
                    case OP_BUYSTOP  :
                    case OP_SELLSTOP :
                    case OP_BUYLIMIT :
                    case OP_SELLLIMIT: check = OrderDelete(OrderTicket()); text = "удалить отложенный"; break;
                    default          : return(0);
                }
                if (check) {
                   j--;
                   break;
                } else {
                    k++;
                    if (k >= Attempts) {
                        if (!IsTesting()) Print("Не удалось ",text," ордер");
                        Sleep(5000);
                        break;
                    }
                    Sleep(1000);
                    RefreshRates();
                }
            }
        }
    }
//---
    return(j);
}
//+------------------------------------------------------------------+
//| TrailingStop                                                     |
//+------------------------------------------------------------------+
void TrailingOrder() {
//---
    bool check;
    double sl_buy  = MarketInfo(NULL, MODE_BID) - TS;
    double sl_sell = MarketInfo(NULL, MODE_ASK) + TS;
//---
    for (int i=0; i<OrdersTotal(); i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && OrderMagicNumber() == Magic && OrderSymbol() == Symbol()) {
            if (OrderType() == OP_BUY && OrderOpenPrice() <= sl_buy && OrderStopLoss()+TS <= sl_buy)
                check = OrderModify(OrderTicket(), OrderOpenPrice(), sl_buy, OrderTakeProfit(), 0, clrGreen);

            if (OrderType() == OP_SELL && OrderOpenPrice() >= sl_sell && OrderStopLoss()-TS >= sl_sell)
                check = OrderModify(OrderTicket(), OrderOpenPrice(), sl_sell, OrderTakeProfit(), 0, clrGreen);
        }
    }
//---
    return;
}
//+------------------------------------------------------------------+
//| Нормальные условия                                               |
//+------------------------------------------------------------------+
bool CheckNormalCondition() {
//---
    return(TakeProfit < StopLoss || TakeProfit <= TrailingStop || MAPrice == PRICE_OPEN || MAPrice == PRICE_HIGH || MAPrice == PRICE_LOW);
}
//+------------------------------------------------------------------+
//| Разрешение на торговлю                                           |
//+------------------------------------------------------------------+
bool TimeAllowed() {
//---
    int week = DayOfWeek();
    int hour = Hour();
//---
    if ((week != 1 || (week == 1 && hour > 1)) &&
        (week != 5 || (week == 5 && hour < 22))) return(true);
//---
    return(false);
}
//+------------------------------------------------------------------+
//| Размер лота                                                      |
//+------------------------------------------------------------------+
double GetSizeLot() {
//---
    double lots = LotsMin;
//---
    if (LotsDepoOne > 0.0 && AccountBalance() >= LotsDepoOne) lots = NormalizeDouble(AccountBalance()/LotsDepoOne*LotsMin, 2);
    if (lots > LotsMax) lots = LotsMax;
    if (lots < LotsMin) lots = LotsMin;
//---
    return(lots);
}
//+------------------------------------------------------------------+
//| Возвращает сумму баланса за определённый период                  |
//+------------------------------------------------------------------+
double GetHistoryBalance() {
//---
    int i, j, k;
    double profit  = 0.0;
    double balance = 0.0;
//---
    ArrayInitialize(ArrayBalance, 0.0);
//---
    for (i=0; i<OrdersHistoryTotal(); i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) && OrderMagicNumber() == Magic && OrderSymbol() == Symbol() && OrderOpenTime() >= StartTimeBalance) {
            if (OrderType() == OP_BUY || OrderType() == OP_SELL) {
                profit   = OrderProfit() + OrderSwap() + OrderCommission();
                balance += profit;

                for (j=0; j<24; j++)
                    if (TimeHour(OrderOpenTime()) == j) break;

                for (k=1; k<6; k++)
                    if (TimeDayOfWeek(OrderOpenTime()) == k) break;

                ArrayBalance[j,k] += profit;
            }
        }
    }
//---
   return(balance);
}
//+------------------------------------------------------------------+
//| Записывает статистику в файл                                     |
//+------------------------------------------------------------------+
void WriteStatistic() {
//---
    double balance = GetHistoryBalance();
//---
    // Название файла
    string filename = Path + "Statistic_" + Symbol() + "_#" + (string)Magic + ".txt";
//---
    // Запись в файл
    int filehandle = FileOpen(filename, FILE_CSV|FILE_WRITE, "\t");
//---
    FileWrite(filehandle, "TimeFrame", "M"+(string)TimeFrame);
    FileWrite(filehandle, "TakeProfit", (string)TakeProfit+"п.");
    FileWrite(filehandle, "StopLoss", (string)StopLoss+"п.");
    FileWrite(filehandle, "TrailingStop", (string)TrailingStop+"п.");
    FileWrite(filehandle, "NumOrder", (string)NumOrder);
    FileWrite(filehandle, "Shift", (string)Shift);
    FileWrite(filehandle, "");
    FileWrite(filehandle, "Periods MA + ATR", PeriodName);
    FileWrite(filehandle, "MAMethode", (string)MAMethode);
    FileWrite(filehandle, "MAPrice", (string)MAPrice);
    FileWrite(filehandle, "");
    FileWrite(filehandle, "Час", "|", "Сумма", "|", "Пн", "Вт", "Ср", "Чт", "Пт");
    FileWrite(filehandle, " ", "|", " ", "|");
//---
    for (int i=0; i<24; i++) {
        double depohour = 0.0;
        for (int j=1; j<6; j++) {
            depohour += ArrayBalance[i,j];
            ArrayBalance[j-1,0] += ArrayBalance[i,j];
        }
        FileWrite(filehandle, i, "|", DoubleToString(depohour, 2), "|", DoubleToString(ArrayBalance[i,1], 2), DoubleToString(ArrayBalance[i,2], 2), DoubleToString(ArrayBalance[i,3], 2), DoubleToString(ArrayBalance[i,4], 2), DoubleToString(ArrayBalance[i,5], 2));
    }
    FileWrite(filehandle, " ", "|", " ", "|");
    FileWrite(filehandle, "Баланс:", " ", DoubleToString(balance, 2), "|", DoubleToString(ArrayBalance[0,0], 2), DoubleToString(ArrayBalance[1,0], 2), DoubleToString(ArrayBalance[2,0], 2), DoubleToString(ArrayBalance[3,0], 2), DoubleToString(ArrayBalance[4,0], 2));
    FileClose(filehandle);
//---
    return;
}
//+------------------------------------------------------------------+
//| Возвращает описание ошибки                                       |
//+------------------------------------------------------------------+
string ErrorDescription(int code) {
//---
    string error;
//---
    switch(code) {
        // Коды ошибок от торгового сервера:
        case 0   : error = "Нет ошибки";                                               break;
        case 1   : error = "Нет ошибки, но результат неизвестен";                      break;
        case 2   : error = "Общая ошибка";                                             break;
        case 3   : error = "Неправильные параметры";                                   break;
        case 4   : error = "Торговый сервер занят";                                    break;
        case 5   : error = "Старая версия клиентского терминала";                      break;
        case 6   : error = "Нет связи с торговым сервером";                            break;
        case 7   : error = "Недостаточно прав";                                        break;
        case 8   : error = "Слишком частые запросы";                                   break;
        case 9   : error = "Недопустимая операция нарушающая функционирование сервера";break;
        case 64  : error = "Счет заблокирован";                                        break;
        case 65  : error = "Неправильный номер счета";                                 break;
        case 128 : error = "Истек срок ожидания совершения сделки";                    break;
        case 129 : error = "Неправильная цена";                                        break;
        case 130 : error = "Неправильные стопы";                                       break;
        case 131 : error = "Неправильный объем";                                       break;
        case 132 : error = "Рынок закрыт";                                             break;
        case 133 : error = "Торговля запрещена";                                       break;
        case 134 : error = "Недостаточно денег для совершения операции";               break;
        case 135 : error = "Цена изменилась";                                          break;
        case 136 : error = "Нет цен";                                                  break;
        case 137 : error = "Брокер занят";                                             break;
        case 138 : error = "Новые цены";                                               break;
        case 139 : error = "Ордер заблокирован и уже обрабатывается";                  break;
        case 140 : error = "Разрешена только покупка";                                 break;
        case 141 : error = "Слишком много запросов";                                   break;
        case 145 : error = "Модификация запрещена, т.к. ордер слишком близок к рынку"; break;
        case 146 : error = "Подсистема торговли занята";                               break;
        case 147 : error = "Использование даты истечения ордера запрещено брокером";   break;
        case 148 : error = "Количество открытых и отложенных ордеров достигло предела";break;
        case 149 : error = "Попытка открыть противоположную позицию к уже существующей в случае, если хеджирование запрещено";break;
        case 150 : error = "Попытка закрыть позицию в противоречии с правилом FIFO";   break;

        // Коды ошибок выполнения MQL4-программы:
        case 4000: error = "Нет ошибки";                                               break;
        case 4001: error = "Неправильный указатель функции";                           break;
        case 4002: error = "Индекс массива - вне диапазона";                           break;
        case 4003: error = "Нет памяти для стека функций";                             break;
        case 4004: error = "Переполнение стека после рекурсивного вызова";             break;
        case 4005: error = "На стеке нет памяти для передачи параметров";              break;
        case 4006: error = "Нет памяти для строкового параметра";                      break;
        case 4007: error = "Нет памяти для временной строки";                          break;
        case 4008: error = "Неинициализированная строка";                              break;
        case 4009: error = "Неинициализированная строка в массиве";                    break;
        case 4010: error = "Нет памяти для строкового массива";                        break;
        case 4011: error = "Слишком длинная строка";                                   break;
        case 4012: error = "Остаток от деления на ноль";                               break;
        case 4013: error = "Деление на ноль";                                          break;
        case 4014: error = "Неизвестная команда";                                      break;
        case 4015: error = "Неправильный переход";                                     break;
        case 4016: error = "Неинициализированный массив";                              break;
        case 4017: error = "Вызовы DLL не разрешены";                                  break;
        case 4018: error = "Невозможно загрузить библиотеку";                          break;
        case 4019: error = "Невозможно вызвать функцию";                               break;
        case 4020: error = "Вызовы внешних библиотечных функций не разрешены";         break;
        case 4021: error = "Недостаточно памяти для строки, возвращаемой из функции";  break;
        case 4022: error = "Система занята";                                           break;
        case 4050: error = "Неправильное количество параметров функции";               break;
        case 4051: error = "Недопустимое значение параметра функции";                  break;
        case 4052: error = "Внутренняя ошибка строковой функции";                      break;
        case 4053: error = "Ошибка массива";                                           break;
        case 4054: error = "Неправильное использование массива-таймсерии";             break;
        case 4055: error = "Ошибка пользовательского индикатора";                      break;
        case 4056: error = "Массивы несовместимы";                                     break;
        case 4057: error = "Ошибка обработки глобальныех переменных";                  break;
        case 4058: error = "Глобальная переменная не обнаружена";                      break;
        case 4059: error = "Функция не разрешена в тестовом режиме";                   break;
        case 4060: error = "Функция не разрешена";                                     break;
        case 4061: error = "Ошибка отправки почты";                                    break;
        case 4062: error = "Ожидается параметр типа string";                           break;
        case 4063: error = "Ожидается параметр типа integer";                          break;
        case 4064: error = "Ожидается параметр типа double";                           break;
        case 4065: error = "В качестве параметра ожидается массив";                    break;
        case 4066: error = "Запрошенные исторические данные в состоянии обновления";   break;
        case 4067: error = "Ошибка при выполнении торговой операции";                  break;
        case 4068: error = "Ресурс не найден";                                         break;
        case 4069: error = "Ресурс не поддерживается";                                 break;
        case 4070: error = "Дубликат ресурса";                                         break;
        case 4071: error = "Ошибка инициализации пользовательского индикатора";        break;
        case 4072: error = "Ошибка загрузки пользовательского индикатора";             break;
        case 4073: error = "Нет исторических данных";                                  break;
        case 4074: error = "Не хватает памяти для исторических данных";                break;
        case 4075: error = "Не хватает памяти для расчёта индикатора";                 break;
        case 4099: error = "Конец файла";                                              break;
        case 4100: error = "Ошибка при работе с файлом";                               break;
        case 4101: error = "Неправильное имя файла";                                   break;
        case 4102: error = "Слишком много открытых файлов";                            break;
        case 4103: error = "Невозможно открыть файл";                                  break;
        case 4104: error = "Несовместимый режим доступа к файлу";                      break;
        case 4105: error = "Ни один ордер не выбран";                                  break;
        case 4106: error = "Неизвестный символ";                                       break;
        case 4107: error = "Неправильный параметр цены для торговой функции";          break;
        case 4108: error = "Неверный номер тикета";                                    break;
        case 4109: error = "Торговля не разрешена";                                    break;
        case 4110: error = "Длинные позиции не разрешены";                             break;
        case 4111: error = "Короткие позиции не разрешены";                            break;
        case 4200: error = "Объект уже существует";                                    break;
        case 4201: error = "Запрошено неизвестное свойство объекта";                   break;
        case 4202: error = "Объект не существует";                                     break;
        case 4203: error = "Неизвестный тип объекта";                                  break;
        case 4204: error = "Нет имени объекта";                                        break;
        case 4205: error = "Ошибка координат объекта";                                 break;
        case 4206: error = "Не найдено указанное подокно";                             break;
        case 4207: error = "Ошибка при работе с объектом";                             break;
        default  : error = "Неизвестная ошибка";                                       break;
    }
//---
    return(error);
}
//+------------------------------------------------------------------+
//| Вывод информации                                                 |
//+------------------------------------------------------------------+
void SetComment(int error) {
//---
    Comment("---------------------------------------------------------",
            "\n",Title," [M",(string)TimeFrame,"] #",(string)Magic,"\n"
            "---------------------------------------------------------",
            "\nTakeProfit: ",(string)TakeProfit,"п.",
            "\nStopLoss: ",(string)StopLoss,"п.",
            "\nTrailingStop: ",(string)TrailingStop,"п.",
            "\nLots: ",DoubleToString(Lots, 2),
            "\n-------------",
            "\nPeriod: ",PeriodName,
            "\n-------------",
            "\nProfit: ",DoubleToString(ProfitBuy+ProfitSell, 2)," (",DoubleToString(ProfitBuy, 2),"/",DoubleToString(ProfitSell, 2),")",
            "\nБаланс с ",TimeToString(StartTimeBalance, TIME_DATE)," по текущий момент: ",DoubleToString(Balance, 2));
//---
    if (error > 0) Print("№",(string)error," ",ErrorDescription(error));
//---
    return;
}
//+------------------------------------------------------------------+
//| end of expert                                                    |
//+------------------------------------------------------------------+