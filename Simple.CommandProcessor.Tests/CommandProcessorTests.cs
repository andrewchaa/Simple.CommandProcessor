using System.Threading.Tasks;
using Machine.Specifications;
using Ninject;

namespace Simple.CommandProcessor.Tests
{
    public class CommandProcessorTests
    {
        [Subject("Test")]
        public class When_issue_a_simple_command_without_dependencies
        {
            private static IProcessCommand _processor;
            private static SimpleCommand _simpleCommand;
            private static string _testMessage;

            Establish context = () =>
            {
                var registry = CommandRegistry.New(new StandardKernel());
                registry.Register<SimpleCommand, SimpleCommandHandler>();
                
                _testMessage = "Test";
                _simpleCommand = new SimpleCommand(_testMessage);
                _processor = new Simple.CommandProcessor.CommandProcessor();
            };

            Because of = () => _processor.Send(_simpleCommand);

            It should_execute_the_handler_of_the_command = () => _simpleCommand.Message.ShouldEqual(_testMessage);
        }

        [Subject("Test")]
        public class When_issue_a_command_with_dependencies
        {
            private static IProcessCommand _processor;
            private static ComplexCommand _complexCommand;
            private static string _message;
            private static int _age;
            private static string _sex;

            Establish context = () =>
            {
                var kernel = new StandardKernel();
                kernel.Bind<IFormatMessage>().To<MessageFormatter>();

                var registry = CommandRegistry.New(kernel);
                registry.Register<ComplexCommand, ComplexCommandHandler>();

                _age = 10;
                _sex = "Female";
                _complexCommand = new ComplexCommand(_age, _sex);
                _processor = new Simple.CommandProcessor.CommandProcessor();
                _message = new MessageFormatter().Format(_age, _sex);
            };

            Because of = () => _processor.Send(_complexCommand);

            It should_execute_the_handler_of_the_command = () => _complexCommand.Message.ShouldEqual(_message);
        }

        public class ComplexCommand : Command
        {
            public int Age { get; private set; }
            public string Sex { get; private set; }
            public string Message { get; set; }

            public ComplexCommand(int age, string sex)
            {
                Age = age;
                Sex = sex;
            }
        }

        public class ComplexCommandHandler : IHandleCommand<ComplexCommand>
        {
            private readonly IFormatMessage _messageFormatter;

            public ComplexCommandHandler(IFormatMessage messageFormatter)
            {
                _messageFormatter = messageFormatter;
            }

            public Task Handle(ComplexCommand command)
            {
                command.Message = _messageFormatter.Format(command.Age, command.Sex);

                return Task.FromResult(0);
            }
        }

        public interface IFormatMessage
        {
            string Format(int age, string sex);
        }

        public class MessageFormatter : IFormatMessage
        {
            public string Format(int age, string sex)
            {
                return $"Jane is {age} old {sex}";
            }
        }

        public class SimpleCommandHandler : IHandleCommand<SimpleCommand>
        {
            public Task Handle(SimpleCommand command)
            {
                command.Result = command.Message;

                return Task.FromResult(0);
            }
        }

        public class SimpleCommand : Command
        {
            public string Message { get; set; }
            public string Result { get; set; }

            public SimpleCommand(string message)
            {
                Message = message;
            }
        }


    }

}
