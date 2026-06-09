interface Props {
  onSignedIn: () => void;
}

export function LoginScreen({ onSignedIn }: Props) {
  return (
    <div className="min-h-screen bg-brand-900 flex items-center justify-center p-6">
      <div className="max-w-md w-full bg-white rounded-xl shadow-2xl p-8">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 bg-brand-500 rounded" aria-hidden />
          <h1 className="text-2xl font-semibold text-brand-900">BCWMSApp</h1>
        </div>
        <h2 className="text-xl font-semibold mb-2">Sign in</h2>
        <p className="text-slate-600 mb-6 text-sm">
          Sign in with your Microsoft Entra ID work account.
        </p>
        <button
          type="button"
          onClick={onSignedIn}
          className="w-full bg-brand-500 hover:bg-brand-700 text-white font-medium py-2.5 rounded transition"
        >
          Sign in with Microsoft
        </button>
        <p className="mt-6 text-xs text-slate-500 text-center">
          Warehouse Management for Business Central · v0.1.0
        </p>
      </div>
    </div>
  );
}
