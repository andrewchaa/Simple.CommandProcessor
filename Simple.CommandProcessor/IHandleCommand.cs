using System.Threading.Tasks;

namespace Simple.CommandProcessor
{
    public interface IHandleCommand<T>
    {
        Task Handle(T command);
    }
}