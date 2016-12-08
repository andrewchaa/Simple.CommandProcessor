using System;
using System.Collections.Concurrent;
using Ninject;

namespace Simple.CommandProcessor
{
    public class CommandRegistry
    {
        private readonly IKernel _kernel;

        private CommandRegistry(IKernel kernel)
        {
            _kernel = kernel;
        }

        private static readonly ConcurrentDictionary<Type, Type> TypeRegistry = new ConcurrentDictionary<Type, Type>();

        public static CommandRegistry New(IKernel kernel)
        {
            Registry = new CommandRegistry(kernel);
            return Registry;
        }

        public static CommandRegistry Registry { get; private set; }
        
        public void Register<T, T1>() where T : Command where T1 : IHandleCommand<T>
        {
            TypeRegistry.TryAdd(typeof(T), typeof(T1));
        }

        public IHandleCommand<T> GetCommandHandlerFor<T>()
        {
            Type handlerType;
            var handlerExist = TypeRegistry.TryGetValue(typeof (T), out handlerType);
            if (!handlerExist)
                throw new CannotFindCommandHandlerException($"Cannot find the registered handler for {typeof (T)}");

            return _kernel.Get(handlerType) as IHandleCommand<T>;
        }
    }
}