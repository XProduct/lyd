using FlacPlayer.Remote;

namespace FlacPlayer
{
    public interface IWebSocketService
    {
        void Start();
        void Stop();
        void SetControl(IRemoteControl control);
        void ApplyPort(int port);
        int Port { get; }
        string DiscoverabilityHint { get; }
        bool IsRunning { get; }
    }
}