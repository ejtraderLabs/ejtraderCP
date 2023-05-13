#property copyright   "Copyright 2023, Ejtrader"
#property link        "https://github.com/ejtraderlabs/ejtraderCP"
#property version     "1.12"
#property description "MT4 Copy Trade Subscriber Application. Subscribe order status from source signal trader."
#property strict
#include <Trade\Trade.mqh>


CTrade trade;




#include <Zmq/Zmq.mqh>
#include <ejtrader/ServerMap.mqh>

//--- Inputs
enum ServerList
{
    A,  // BITCOINNANO
    B,  // LOCAL
    C,  // CUSTOMREMOTE
};

input ServerList ServicesSelect = A; // SERVER

string ServerNames[] = {"BITCOINNANO", "LOCAL", "CUSTOM"};
input string ServerAddress = "localhost:5555"; // CUSTOM SERVER IF AVALIBLE
input string CustomServerPublicKey = ""; // CUSTOM SERVER PublicKey

input string genpub="6]&Tu69}*8wPDW&]dZ*@/NT<j):464xNauDn}&yM"; // Public Key
input string gensec="iik8-mg<Q.tN47Va%ZX&e%0NB)O{V>+:NISEd!(/"; // secret Key



string ServerKey="JY%:%zEd6w]<6Z<%d]Ug&oy*-)XmAHJOFjfQUt8t"; // Server Public key

input string Server                  = "tcp://localhost:5559";  // Subscribe server ip
input uint   ServerDelayMilliseconds = 300;                     // Subscribe from server delay milliseconds (Default is 300)
input bool   ServerReal              = false;                   // Under real server (Default is false)
input string SignalAccount           = "";                      // Subscribe signal account from server (Default is empty)
input double MinLots                 = 0.00;                    // Limit the minimum lots (Default is 0.00)
input double MaxLots                 = 0.00;                    // Limit the maximum lots (Default is 0.00)
input double PercentLots             = 100;                     // Lots Percent from Signal (Default is 100)
input int    Slippage                = 3;
input bool   AllowOpenTrade          = true;                    // Allow Open a New Order (Default is true)
input bool   AllowCloseTrade         = true;                    // Allow Close a Order (Default is true)
input bool   AllowModifyTrade        = true;                    // Allow Modify a Order (Default is true)
input string AllowSymbols            = "";                      // Allow Trading Symbols (Ex: EURUSDq,EURUSDx,EURUSDa)
input bool   InvertOrder             = false;                   // Invert original trade direction (Default is false)
input double MinFreeMargin           = 0.00;                    // Minimum Free Margin to Open a New Order (Default is 0.00)
input string SymbolPrefixAdjust      = "";                      // Adjust the Symbol Name as Local Symbol Name (Ex: d=q,d=)

//--- Globales Struct
struct ClosedOrder
  {
   int               s_login;
   int               s_orderid;
   int               s_before_orderid;
   int               orderid;
  };

struct SymbolPrefix
  {
   string            s_name;
   string            d_name;
  };

//--- Globales Application
const string app_name    = "Ejtrader Copy Trader Client";

//--- Globales ZMQ
Context context;
Socket  subscriber(context, ZMQ_SUB);

string zmq_server        = "";
uint   zmq_subdelay      = 0;
bool   zmq_runningstatus = false;

//--- Globales Order
double order_minlots     = 0.00;
double order_maxlots     = 0.00;
double order_percentlots = 100;
int    order_slippage    = 0;
bool   order_allowopen   = true;
bool   order_allowclose  = true;
bool   order_allowmodify = true;
bool   order_invert      = false;

//--- Globales Account
int    account_subscriber    = 0;
double account_minmarginfree = 0.00;

//--- Globales File
string       local_drectoryname    = "Data";
string       local_pclosedfilename = "partially_closed.bin";
ClosedOrder  local_pclosed[];

SymbolPrefix local_symbolprefix[];
string       local_symbolallow[];
int          symbolprefix_size     = 0;
int          symbolallow_size      = 0;


int MILLISECOND_TIMER = 1;

//+------------------------------------------------------------------+
//| Expert program start function                                    |
//+------------------------------------------------------------------+
void OnInit()
  {
   if(DetectEnvironment() == false)
     {
      Alert("Error: The property is fail, please check and try again.");
      return;
     }

   StartZmqClient();
  }

//+------------------------------------------------------------------+
//| Override deinit function                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   StopZmqClient();
  }

//+------------------------------------------------------------------+
//| Detect the script parameters                                     |
//+------------------------------------------------------------------+
bool DetectEnvironment()
  {


   if(!TERMINAL_DLLS_ALLOWED)
     {
      Print("DLL call is not allowed. ", app_name, " cannot run.");
      return false;
     }

   zmq_server        = Server;
   zmq_subdelay      = (ServerDelayMilliseconds > 0) ? ServerDelayMilliseconds : 10;
   zmq_runningstatus = false;

   order_minlots     = MinLots;
   order_maxlots     = MaxLots;
   order_percentlots = (PercentLots > 0) ? PercentLots : 100;
   order_slippage    = Slippage;
   order_allowopen   = AllowOpenTrade;
   order_allowclose  = AllowCloseTrade;
   order_allowmodify = AllowModifyTrade;
   order_invert      = InvertOrder;

   account_subscriber    = (SignalAccount != "") ? StringToInteger(SignalAccount) : -1;
   account_minmarginfree = MinFreeMargin;


// Load the Symbol prefix maps
   if(SymbolPrefixAdjust != "")
     {
      string symboldata[];
      int    symbolsize  = StringSplit(SymbolPrefixAdjust, ',', symboldata);
      int    symbolindex = 0;

      ArrayResize(local_symbolprefix, symbolsize);

      for(symbolindex=0; symbolindex<symbolsize; symbolindex++)
        {
         string prefixdata[];
         int    prefixsize = StringSplit(symboldata[symbolindex], '=', prefixdata);

         if(prefixsize == 2)
           {
            local_symbolprefix[symbolindex].s_name = prefixdata[0];
            local_symbolprefix[symbolindex].d_name = prefixdata[1];
           }
        }

      symbolprefix_size = symbolsize;
     }

// Load the Symbol allow map
   if(AllowSymbols != "")
     {
      string symboldata[];
      int    symbolsize  = StringSplit(AllowSymbols, ',', symboldata);
      int    symbolindex = 0;

      ArrayResize(local_symbolallow, symbolsize);

      for(symbolindex=0; symbolindex<symbolsize; symbolindex++)
        {
         if(symboldata[symbolindex] == "")
            continue;

         local_symbolallow[symbolindex] = symboldata[symbolindex];
        }

      symbolallow_size = symbolsize;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Start the zmq client                                             |
//+------------------------------------------------------------------+
void StartZmqClient()
  {
   if(zmq_server == "")
      return;

   subscriber.setCurvePublicKey(genpub);
   subscriber.setCurveSecretKey(gensec);
   subscriber.setCurveServerKey(ServerKey);

   int result = subscriber.connect(zmq_server);

   if(result != 1)
     {
      Alert("Error: Unable to connect to the server, please check your server settings.");
      return;
     }

// Load closed order to memory
   LocalClosedDataToMemory();

   subscriber.subscribe("");

   ZmqMsg received;
   string message         = "";
   int    singallogin     = -1;
   string singalorderdata = "";

   uint delay       = zmq_subdelay;
   uint ticketstart = 0;
   uint tickcount   = 0;

   zmq_runningstatus = true;

   Print("Load Subscribe: ", zmq_server);

   if(account_subscriber > 0)
      Print("Signal Account: " + account_subscriber);

   while(!IsStopped())
     {
      ticketstart = GetTickCount();

      subscriber.recv(received, true);
      message = received.getData();
      // AccountInfoDouble(ACCOUNT_EQUITY)
      if(message != "" && ACCOUNT_EQUITY > 0.00)
        {
         singallogin     = -1;
         singalorderdata = "";

         ParseMessage(message, singallogin, singalorderdata);

         if(singallogin > 0)
           {
            if(account_subscriber <= 0 || account_subscriber == singallogin)
               ParseOrderFromSingal(singallogin, singalorderdata);
           }

         continue;
        }

      tickcount = GetTickCount() - ticketstart;

      if(delay > tickcount)
         Sleep(delay-tickcount-2);
     }
  }

//+------------------------------------------------------------------+
//| Stop the zmq client                                              |
//+------------------------------------------------------------------+
void StopZmqClient()
  {
   if(zmq_server == "")
      return;

// Save local closed order to file
   LocalClosedDataToFile();

   Print("UnLoad Subscribe: ", zmq_server);

   ArrayFree(local_pclosed);
   ArrayFree(local_symbolprefix);
   ArrayFree(local_symbolallow);

   if(zmq_runningstatus == true)
     {
      subscriber.unsubscribe("");
      subscriber.disconnect(zmq_server);
     }
  }

//+------------------------------------------------------------------+
//| Parse the message from server signal                             |
//+------------------------------------------------------------------+
bool ParseMessage(const string message,
                  int &login,
                  string &orderdata)
  {
   if(message == "")
      return false;

   string messagedata[];
   int    size = StringSplit(message, ' ', messagedata);

   login     = -1;
   orderdata = "";

   if(size != 2)
      return false;

   login     = StringToInteger(messagedata[0]);
   orderdata = messagedata[1];

   return true;
  }

//+------------------------------------------------------------------+
//| Parse the order from signal message                              |
//+------------------------------------------------------------------+
bool ParseOrderFromSingal(const int login,
                          const string ordermessage)
  {
   if(login <= 0 || ordermessage == "")
      return false;

   string orderdata[];
   int    size = StringSplit(ordermessage, '|', orderdata);

   if(size != 9)
      return false;

// Order data from signal
   string op            = orderdata[0];
   string symbol        = orderdata[1];
//int    orderid       = StringToInteger(orderdata[2]);
   int    orderid       = -1;
   int    beforeorderid = -1;
   int    type          = StringToInteger(orderdata[3]);
   double openprice     = StringToDouble(orderdata[4]);
   double closeprice    = StringToDouble(orderdata[5]);
   double lots          = StringToDouble(orderdata[6]);
   double sl            = StringToDouble(orderdata[7]);
   double tp            = StringToDouble(orderdata[8]);

   string orderiddata[];
   int    orderidsize = StringSplit(orderdata[2], '_', orderiddata);

   symbol = GetOrderSymbolPrefix(symbol);

// Partially closed a trade
// Partially closed a trade will have 2 order id (orderid and before orderid)
   if(orderidsize == 2)
     {
      orderid       = StringToInteger(orderiddata[0]);
      beforeorderid = StringToInteger(orderiddata[1]);
     }
   else
     {
      orderid = StringToInteger(orderdata[2]);
     }

   return MakeOrder(login, op, symbol, orderid, beforeorderid, type, openprice, closeprice, lots, sl, tp);
  }

//+------------------------------------------------------------------+
//| Make a order by signal message (Market and Pending Order)        |
//+------------------------------------------------------------------+
bool MakeOrder(const int login,
               const string op,
               const string symbol,
               const int orderid,
               const int beforeorderid,
               const int type,
               const double openprice,
               const double closeprice,
               const double lots,
               const double sl,
               const double tp)
  {
   if(login <= 0 || symbol == "" || orderid == 0)
      return false;

   if(GetOrderSymbolAllowed(symbol) == false)
      return false;

   int    ticketid    = -1;
   string comment     = StringFormat("%d|%d", login, orderid);
   bool   orderstatus = false;
   bool   localstatus = false;

   if(op == "OPEN")
     {
      ticketid = FindOrderBySignalComment(symbol, orderid);

      if(ticketid <= 0)
        {
         ticketid = MakeOrderOpen(symbol, type, openprice, lots, sl, tp, comment);

         Print("Open:", symbol, ", Type:", type, ", TicketId:", ticketid);
        }
     }
   else
      if(op == "CLOSED")
        {
         ticketid = FindOrderBySignalComment(symbol, orderid);

         if(ticketid <= 0)
           {
            ticketid = FindPartClosedOrderByLocal(symbol, orderid);
           }

         if(ticketid > 0)
           {
            orderstatus = MakeOrderClose(ticketid, symbol, type, closeprice, lots, sl, tp);

            Print("Closed:", symbol, ", Type:", type);
           }
        }
      else
         if(op == "PCLOSED")
           {
            ticketid = FindOrderBySignalComment(symbol, beforeorderid);
            // Parcial Close
            if(ticketid <= 0)
              {
               ticketid = FindPartClosedOrderByLocal(symbol, beforeorderid);
              }

            if(ticketid > 0)
              {
               //string localmessage = StringFormat("%d|%d-%d|%d", login, orderid, beforeorderid, ticketid);
               localstatus = LocalClosedDataSave(login, orderid, beforeorderid, ticketid);
               orderstatus = MakeOrderPartiallyClose(ticketid, symbol, type, closeprice, lots, sl, tp);

               Print("Partially Closed:", symbol, ", Type:", type);
              }
           }
         else
            if(op == "MODIFY")
              {
               ticketid = FindOrderBySignalComment(symbol, orderid);

               if(ticketid <= 0)
                 {
                  ticketid = FindPartClosedOrderByLocal(symbol, orderid);
                 }

               if(ticketid > 0)
                 {
                  orderstatus = MakeOrderModify(ticketid, symbol, openprice, sl, tp);

                  Print("Modify:", symbol, ", Type:", type);
                 }
              }

   return (ticketid > 0) ? true : false;
  }

//+------------------------------------------------------------------+
//| Make a market or pending order by signal message                 |
//+------------------------------------------------------------------+
int MakeOrderOpen(const string symbol,
                  const int type,
                  const double openprice,
                  const double lots,
                  const double sl,
                  const double tp,
                  const string comment)
  {
   ulong ticketid = -1;

// Allow signal to open the order
// Symbol must not be empty
   if(order_allowopen == false || symbol == "")
      return ticketid;

// Allow Expert Advisor to open the order
   if(!TERMINAL_DLLS_ALLOWED)
      return ticketid;

// Check if account margin free is less than settings
   if(account_minmarginfree > 0.00 && AccountInfoDouble(ACCOUNT_MARGIN_FREE) < account_minmarginfree)
      return ticketid;

   double vprice = openprice;
   double vlots = GetOrderLots(symbol, lots);
   int    vtype = type;

// The parameter price must be greater than zero
   if(vprice <= 0.00)
      vprice = SymbolInfoDouble(symbol, SYMBOL_ASK);

// Invert the origional order
   if(order_invert)
     {
      switch(vtype)
        {
         case ORDER_TYPE_BUY:
            vtype = ORDER_TYPE_SELL;
            break;

         case ORDER_TYPE_SELL:
            vtype = ORDER_TYPE_BUY;
            break;

         case ORDER_TYPE_BUY_LIMIT:
            vtype = ORDER_TYPE_SELL_LIMIT;
            break;

         case ORDER_TYPE_BUY_STOP:
            vtype = ORDER_TYPE_SELL_STOP;
            break;

         case ORDER_TYPE_SELL_LIMIT:
            vtype = ORDER_TYPE_BUY_LIMIT;
            break;

         case ORDER_TYPE_SELL_STOP:
            vtype = ORDER_TYPE_BUY_STOP;
            break;
        }
     }

   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.symbol = symbol;
   request.volume = vlots;
   request.sl = sl;
   request.tp = tp;
   request.deviation = order_slippage;
   request.magic = 0;
   request.comment = comment;
   request.type_filling = ORDER_FILLING_FOK;

   switch(vtype)
     {
      case ORDER_TYPE_BUY:
      case ORDER_TYPE_SELL:
         request.action = TRADE_ACTION_DEAL;
         request.type = vtype;
         request.price = vprice;
         break;

      case ORDER_TYPE_BUY_LIMIT:
      case ORDER_TYPE_BUY_STOP:
      case ORDER_TYPE_SELL_LIMIT:
      case ORDER_TYPE_SELL_STOP:
         if(openprice > 0.00)
           {
            request.action = TRADE_ACTION_PENDING;
            request.type = vtype;
            request.price = openprice;
           }
         break;
     }

   if(OrderSend(request, result))
     {
      Print("OrderSend successful, ticket number is ",result.order);
      ticketid = result.order;
     }
   else
     {
      Print("OrderSend failed with error ",GetLastError());
     }

   return ticketid;
  }



//+------------------------------------------------------------------+
//| Make a order close by signal message                             |
//+------------------------------------------------------------------+
bool MakeOrderClose(const ulong ticketid,
                    const string symbol,
                    const int type,
                    const double closeprice,
                    const double lots,
                    const double sl,
                    const double tp)
  {
   bool result = false;

// Allow signal to close the order
// The parameter ticketid must be greater than zero
   if(order_allowclose == false || ticketid <= 0)
      return result;

// Allow Expert Advisor to close the order
   if(!TERMINAL_DLLS_ALLOWED)
      return result;

// For pending orders
   if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)
     {
      if(OrderSelect(ticketid))
        {
      
         result = trade.OrderDelete(ticketid);
        }
     }
   else // For open positions
     {
      if(PositionSelectByTicket(ticketid) == true)
        {
         double price = closeprice;

         if(price <= 0.00)
            price = SymbolInfoDouble(symbol, SYMBOL_BID);

         
         result = trade.PositionClose(ticketid);
        }
     }

   return result;
  }



//+------------------------------------------------------------------+
//| Make a partially order close by signal message                   |
//+------------------------------------------------------------------+
bool MakeOrderPartiallyClose(const ulong ticketid,
                             const string symbol,
                             const int type,
                             const double closeprice,
                             const double lots,
                             const double sl,
                             const double tp)
  {
   bool result = false;

// Allow signal to close the order
// The parameter ticketid must be greater than zero
   if(order_allowclose == false || ticketid <= 0)
      return result;

// Allow Expert Advisor to close the order
   if(!TERMINAL_DLLS_ALLOWED)
      return result;


// For pending orders, do nothing
   if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_SELL_STOP)
     {
      return result;
     }
// For open positions
   else
     {
      if(PositionSelectByTicket(ticketid))
        {
         double price      = closeprice;
         double vcloselots = PositionGetDouble(POSITION_VOLUME);

         // Calculate the lots to close
         double vlots = lots;
         if(vcloselots - lots > 0)
           {
            vlots = vcloselots - lots;
           }

         if(price <= 0.00)
            price = SymbolInfoDouble(symbol, SYMBOL_BID);

         // Close the position partially
         trade.PositionClosePartial(ticketid, vlots);
         result = true;
        }
     }

   return result;
  }

//+------------------------------------------------------------------+
//| Make a order modify by signal message                            |
//+------------------------------------------------------------------+
bool MakeOrderModify(const ulong ticketid,
                     const string symbol,
                     const double openprice,
                     const double sl,
                     const double tp)
  {
   bool modifyResult = false;

   // Allow signal to modify the order
   // The parameter ticketid must be greater than zero
   if(order_allowmodify == false || ticketid <= 0)
      return modifyResult;

   // Allow Expert Advisor to modify the order
   if(!TERMINAL_DLLS_ALLOWED)
      return modifyResult;


   if(PositionSelectByTicket(ticketid))
   {
      // Modify an open position
      modifyResult = trade.PositionModify(ticketid, sl, tp);
   }
   else 
   {
      MqlTradeRequest request={};
      MqlTradeResult  tradeResult={};

      request.action   = TRADE_ACTION_MODIFY;
      request.order    = ticketid;
      request.symbol   = symbol;
      request.sl       = sl;
      request.tp       = tp;
      request.deviation= 10;

      // Send trade request
      if(!OrderSend(request,tradeResult))
      {
         Print("OrderSend failed with error ",GetLastError());
      }
      else
      {
         if(tradeResult.retcode == TRADE_RETCODE_DONE)
         {
            modifyResult = true;
         }
         else
         {
            Print("Modify failed, retcode=",tradeResult.retcode);
         }
      }
   }

   return modifyResult;
  }




//+------------------------------------------------------------------+
//| Get the order lots is greater than or less than max and min lots |
//+------------------------------------------------------------------+
double GetOrderLots(const string symbol, const double lots)
{
   double result = lots;

   if(order_percentlots > 0)
     {
      result = lots * (order_percentlots / 100);
     }

   if(order_minlots > 0.00)
      result = (lots <= order_minlots) ? order_minlots : result;

   if(order_maxlots > 0.00)
      result = (lots >= order_maxlots) ? order_maxlots : result;

   if(order_percentlots > 0)
     {
      double s_maxlots = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double s_mixlots = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

      if(result > s_maxlots)
         result = s_maxlots;

      if(result < s_mixlots)
         result = s_mixlots;
     }

   return result;
}


//+------------------------------------------------------------------+
//| Get the order symbol between A broker and B broker               |
//+------------------------------------------------------------------+
string GetOrderSymbolPrefix(const string symbol)
{
   string result = symbol;

   if(symbolprefix_size == 0)
      return result;

   int symbolsize  = StringLen(symbol);
   int symbolindex = 0;

   for(symbolindex=0; symbolindex<symbolprefix_size; symbolindex++)
     {
      int    prefixsize      = StringLen(local_symbolprefix[symbolindex].s_name);
      string symbolname      = StringSubstr(symbol, 0, symbolsize-prefixsize);
      string tradesymbolname = symbolname + local_symbolprefix[symbolindex].d_name;

      if(symbolname + local_symbolprefix[symbolindex].s_name != symbol)
         continue;

      if(SymbolInfoString(tradesymbolname, SYMBOL_CURRENCY_BASE) != "")
        {
         result = tradesymbolname;

         break;
        }
     }

   return result;
}


//+------------------------------------------------------------------+
//| Get the symbol allowd on trading                                 |
//+------------------------------------------------------------------+
bool GetOrderSymbolAllowed(const string symbol)
{
   bool result = true;

   if(symbolallow_size == 0)
      return result;

// Change result as FALSE when allow list is not empty
   result = false;

   int symbolindex = 0;

   for(symbolindex=0; symbolindex<symbolallow_size; symbolindex++)
     {
      if(local_symbolallow[symbolindex] == "")
         continue;

      if(symbol == local_symbolallow[symbolindex])
        {
         result = true;

         break;
        }
     }

   return result;
}


//+------------------------------------------------------------------+
//| Find a current order by server signal                            |
//+------------------------------------------------------------------+
int FindOrderBySignalComment(const string symbol, const int signal_ticketid)
{
    ulong ticket;
    string comment;
    string symbol_for_order;
    for(int i = 0; i < OrdersTotal(); i++) {
        ticket = OrderGetTicket(i);
        if(ticket > 0) {
            comment = OrderGetString(ORDER_COMMENT);
            symbol_for_order = OrderGetString(ORDER_SYMBOL);
            if(comment == "" || symbol_for_order != symbol)
                continue;
            string singalorderdata[];
            int size = StringSplit(comment, '|', singalorderdata);
            if(size != 2)
                continue;
            if(signal_ticketid == StringToInteger(singalorderdata[1]))
                return ticket;
        }
    }
    return -1;
}



//+------------------------------------------------------------------+
//| Find a history order closed by server signal                     |
//+------------------------------------------------------------------+
int FindClosedOrderByHistoryToComment(const string symbol, const int signal_ticketid)
{
    ulong ticket;
    string comment;
    string symbol_for_order;
    for(int i = 0; i < HistoryOrdersTotal(); i++) {
        ticket = HistoryOrderGetTicket(i);
        if(ticket > 0) {
            comment = HistoryOrderGetString(ticket, ORDER_COMMENT);
            symbol_for_order = HistoryOrderGetString(ticket, ORDER_SYMBOL);
            if(comment == "" || symbol_for_order != symbol)
                continue;
            if(signal_ticketid != HistoryOrderGetInteger(ticket, ORDER_TICKET))
                continue;
            if(StringFind(comment, "to #", 0) >= 0) {
                if(StringReplace(comment, "to #", "") >= 0) {
                    ticket = StringToInteger(comment);
                    if(ticket > 0)
                        return ticket;
                }
            }
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Find a part closed order by server signal                        |
//+------------------------------------------------------------------+
int FindPartClosedOrderByLocal(string symbol, int signal_ticketid) {
    int before_orderid = -1;
    for(int i = 0; i < ArraySize(local_pclosed); i++) {
        if(local_pclosed[i].s_orderid == signal_ticketid) {
            before_orderid = local_pclosed[i].orderid;
            break;
        }
    }
    if(before_orderid > 0) {
        return FindClosedOrderByHistoryToComment(symbol, before_orderid);
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Local closed data save                                           |
//+------------------------------------------------------------------+
bool LocalClosedDataSave(int s_login, int s_orderid, int sl_beforeorderid, int orderid) {
    int local_pclosedsize = ArraySize(local_pclosed);
    if(ArrayResize(local_pclosed, local_pclosedsize + 1)) {
        local_pclosed[local_pclosedsize].s_login = s_login;
        local_pclosed[local_pclosedsize].s_orderid = s_orderid;
        local_pclosed[local_pclosedsize].s_before_orderid = sl_beforeorderid;
        local_pclosed[local_pclosedsize].orderid = orderid;
        return true;
    }
    return false;
}


//+------------------------------------------------------------------+
//| Local closed data to memory                                      |
//+------------------------------------------------------------------+
void LocalClosedDataToMemory() {
    int login = AccountInfoInteger(ACCOUNT_LOGIN);
    string filename = IntegerToString(login) + "_" + local_pclosedfilename;
    int handle = FileOpen(local_drectoryname + "\\" + filename, FILE_READ|FILE_BIN);
    if(handle != INVALID_HANDLE) {
        FileReadArray(handle, local_pclosed);
        FileClose(handle);
    } else {
        Print("Failed to open the closed order file, error ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Local closed data to file                                        |
//+------------------------------------------------------------------+
void LocalClosedDataToFile() {
    int login = AccountInfoInteger(ACCOUNT_LOGIN);
    string filename = IntegerToString(login) + "_" + local_pclosedfilename;
    int handle = FileOpen(local_drectoryname + "\\" + filename, FILE_WRITE|FILE_BIN);
    if(handle != INVALID_HANDLE) {
        int local_pclosedsize = ArraySize(local_pclosed);
        FileSeek(handle, 0, SEEK_END);
        FileWriteArray(handle, local_pclosed, 0, local_pclosedsize);
        FileClose(handle);
    } else {
        Print("Failed to open the closed order file, error ", GetLastError());
    }
}

//+------------------------------------------------------------------+
