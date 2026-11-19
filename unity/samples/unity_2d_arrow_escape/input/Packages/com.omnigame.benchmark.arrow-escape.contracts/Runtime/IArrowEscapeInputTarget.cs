using UnityEngine;

namespace OmniGame.Benchmark.ArrowEscape.V2
{
    /// <summary>
    /// Optional adapter identifying the active visible GameObject used by the ordinary
    /// player-facing pointer route. Implementations may omit it and expose ordinary visible
    /// IPointerClickHandler, Button, or Collider-backed targets instead. The interface
    /// contains no action method.
    /// </summary>
    public interface IArrowEscapeInputTarget
    {
        string ArrowId { get; }

        GameObject PointerTarget { get; }
    }
}
