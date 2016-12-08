using System.Threading.Tasks;

namespace Simple.CommandProcessor
{
    public class CommandProcessor : IProcessCommand
    {
        public async Task SendAsync<T>(T command) where T : Command
        {
            var handler = CommandRegistry.Registry.GetCommandHandlerFor<T>();
            await handler.Handle(command);
        }

        void IProcessCommand.Send<T>(T command)
        {
            var handler = CommandRegistry.Registry.GetCommandHandlerFor<T>();
            handler.Handle(command);
        }

    }
}