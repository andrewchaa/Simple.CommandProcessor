using System;

namespace Simple.CommandProcessor
{
    public class CannotFindCommandHandlerException : Exception
    {
        public CannotFindCommandHandlerException(string message) : base(message) {}
    }
}