namespace BCWMS.PrintAgent.Windows.Infrastructure;

/// <summary>
/// Compile-time product identity. The DKC flavor intentionally uses a distinct
/// executable, mutex, DPAPI entropy and local-data folder so it can run beside
/// the existing WMS agent under the same Windows user without sharing secrets.
/// </summary>
internal static class AgentProduct
{
#if DKC_PRODUCTION
    public const string ProductId = "DynOps.DKCProduction.PrintAgent";
    public const string DisplayName = "DKC Production Print Agent";
    public const string DataFolderName = "DKC Production Print Agent";
    public const string MutexPrefix = "DynOps.DKCProduction.PrintAgent";
    public const string DpapiEntropy = "DynOps.DKCProduction.PrintAgent.Settings.v1";
    public const string PrintJobPrefix = "DKCPROD";
#else
    public const string ProductId = "DynOps.BCWMS.PrintAgent";
    public const string DisplayName = "BCWMS Print Agent";
    public const string DataFolderName = "BCWMS Print Agent";
    public const string MutexPrefix = "DynOps.BCWMS.PrintAgent";
    public const string DpapiEntropy = "DynOps.BCWMS.PrintAgent.Settings.v1";
    public const string PrintJobPrefix = "BCWMS";
#endif
}
