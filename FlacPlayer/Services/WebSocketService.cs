using System;
using System.Threading;

namespace FlacPlayer
{
    public class WebSocketService : IWebSocketService
    {
        public void Start()
        {
            HttpServer httpServer = new MyHttpServer(8080);
            Thread thread = new Thread(new ThreadStart(httpServer.listen));
            thread.Start();
        }
    }
}
