using System.Threading.Tasks;

namespace Simple.CommandProcessor
{
    public interface IProcessCommand
    {
        Task SendAsync<T>(T command) where T : Command;
        void Send<T>(T command) where T : Command;
    }
}