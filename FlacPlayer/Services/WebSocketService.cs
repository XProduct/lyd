using System;
using System.Threading;

namespace FlacPlayer
{
    public class WebSocketService : IWebSocketService
    {
        HttpServer httpServer;
        Thread httpThread;

        public void Start()
        {
            httpServer = new MyHttpServer(8080);
            httpThread = new Thread(new ThreadStart(httpServer.Listen));
            httpThread.Start();
        }

        public void Stop()
        {
            httpServer.Stop();
        }
    }
}
