int ServerPort;     
string service;   
string ServerIP="api.bitcoinnano.org";
#property strict
//+------------------------------------------------------------------+
//| A servicename to port map                                             |
//+------------------------------------------------------------------+
struct PortMap
  {
   string            serviceString;
   int               Port;
  };
//+------------------------------------------------------------------+
//| Automatically select a port for the specified servicename             |
//+------------------------------------------------------------------+
int AutoSelectPort(const PortMap &portMap[],string servicename)
  {
  
   for(int i=0; i<ArraySize(portMap)-1; i++)
     {
      if(portMap[i].serviceString==servicename)
        {
         return portMap[i].Port;
        }
     }
   Alert("WRONG SERVICE" ,_servicename);
   
   return 0;
  }
// edit here to update auto port mapping
PortMap PortMaps[]=
  {
     
     {"COPYTRADE", 5555},
     {"DATAFEED", 5555},
     {"NEWS", 5555},
     {"FUNDAMENTAL", 5555},
     {"DATAFEED", 5555},
     {"", NULL}
  
  };
