using UnityEngine;

namespace OmniGame.Benchmark.ArrowEscape.V2
{
    public enum ArrowEscapeUiAction
    {
        Hint = 0,
        Restart = 1,
        NextLevel = 2
    }

    /// <summary>
    /// Optional adapter identifying the real visible player-facing UI target associated
    /// with one public action. Implementations may omit this adapter and expose ordinary
    /// visible Unity UI controls instead. The interface contains no action method.
    /// </summary>
    public interface IArrowEscapeUiInputTarget
    {
        ArrowEscapeUiAction Action { get; }

        GameObject PointerTarget { get; }
    }
}
