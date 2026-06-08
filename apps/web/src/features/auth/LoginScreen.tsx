interface Props {
  onSignedIn: () => void;
}

export function LoginScreen({ onSignedIn }: Props) {
  return (
    <div className="max-w-md mx-auto mt-16 bg-white rounded-xl shadow p-8">
      <h2 className="text-2xl font-semibold mb-2">Sign in</h2>
      <p className="text-slate-600 mb-6">
        Sign in with your Microsoft Entra ID work account to access the BCWMSApp manager
        console.
      </p>
      <button
        type="button"
        onClick={onSignedIn}
        className="w-full bg-brand-500 hover:bg-brand-700 text-white font-medium py-2 rounded transition"
      >
        Sign in with Microsoft
      </button>
      <p className="mt-4 text-xs text-slate-500">
        M0 scaffold: Entra ID OAuth (MSAL) wiring lands in M1.
      </p>
    </div>
  );
}
