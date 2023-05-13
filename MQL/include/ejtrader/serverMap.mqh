#property strict
//+------------------------------------------------------------------+
//| A symbol to port map                                             |
//+------------------------------------------------------------------+
struct ServerMap
  {
   string ServerCheck;
   string ServerOutput; // Alterado de 'int' para 'string'
  };
//+------------------------------------------------------------------+
//| Automatically select a port for the specified symbol             |
//+------------------------------------------------------------------+
string AutoSelectServer(const ServerMap &serverMap[], string ServerName) // Alterado de 'int' para 'string'
  {
   for(int i = 0; i < ArraySize(serverMap) - 1; i++)
     {
      if(serverMap[i].ServerCheck == ServerName)
        {
         return serverMap[i].ServerOutput;
        }
     }
   Alert("Server Not Supported: " ,ServerName);
   
   return "";
  }
// edit here to update auto port mapping
ServerMap ServerMaps[]=
  {
     {"BITCOINNANO", "tcp://api.bitcoinnano.org:5555"},
     {"LOCAL", "tcp://localhos:5555"},
     {"CUSTOM", "tcp://"},
     
     {"", ""}
  };
