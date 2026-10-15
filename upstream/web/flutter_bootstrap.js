{{flutter_js}}
{{flutter_build_config}}

const updateHoldLimitMs = 10000;

function showUpdateOverlay() {
  const style = document.createElement('style');
  style.textContent = `
    #lcs-update-overlay {
      position: fixed;
      inset: 0;
      background: #29251d;
      color: #e9e6cd;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 18px;
      font-family: Georgia, serif;
      font-size: 32px;
      z-index: 9999;
    }
    #lcs-update-overlay .dots {
      display: flex;
      gap: 10px;
    }
    #lcs-update-overlay .dots span {
      width: 12px;
      height: 12px;
      border-radius: 50%;
      background: #a29156;
      animation: lcs-update-dot 1.2s infinite;
    }
    #lcs-update-overlay .dots span:nth-child(2) {
      animation-delay: 0.2s;
    }
    #lcs-update-overlay .dots span:nth-child(3) {
      animation-delay: 0.4s;
    }
    @media (prefers-reduced-motion: reduce) {
      #lcs-update-overlay .dots span { animation: none; }
    }
    @keyframes lcs-update-dot {
      0%, 60%, 100% { transform: translateY(0); opacity: 0.4; }
      30% { transform: translateY(-10px); opacity: 1; }
    }
  `;
  const overlay = document.createElement('div');
  overlay.id = 'lcs-update-overlay';
  const label = document.createElement('div');
  label.textContent = 'Loading LCS Update';
  const dots = document.createElement('div');
  dots.className = 'dots';
  for (let i = 0; i < 3; i++) {
    dots.appendChild(document.createElement('span'));
  }
  overlay.appendChild(label);
  overlay.appendChild(dots);
  document.head.appendChild(style);
  document.body.appendChild(overlay);
  return () => {
    overlay.remove();
    style.remove();
  };
}

async function applyPendingServiceWorkerUpdate() {
  const reg = await navigator.serviceWorker.register('sw.js');
  if (!navigator.serviceWorker.controller) {
    return;
  }
  try {
    await reg.update();
  } catch (e) {
    return;
  }
  const pending = reg.waiting ?? reg.installing;
  if (!pending) {
    return;
  }
  const removeOverlay = showUpdateOverlay();
  await new Promise((resolve) => {
    const onControllerChange = () => {
      clearTimeout(timer);
      window.location.reload();
    };
    const finish = () => {
      removeOverlay();
      pending.removeEventListener('statechange', onStateChange);
      navigator.serviceWorker.removeEventListener(
          'controllerchange', onControllerChange);
      resolve();
    };
    const timer = setTimeout(finish, updateHoldLimitMs);
    const onStateChange = () => {
      if (pending.state === 'installed') {
        pending.postMessage('skipWaiting');
      } else if (pending.state === 'redundant') {
        clearTimeout(timer);
        finish();
      }
    };
    navigator.serviceWorker.addEventListener(
        'controllerchange', onControllerChange);
    pending.addEventListener('statechange', onStateChange);
    onStateChange();
  });
}

function bootApp() {
  _flutter.loader.load({
    config: {
      canvasKitBaseUrl: 'canvaskit/',
    },
  });
}

if ('serviceWorker' in navigator) {
  applyPendingServiceWorkerUpdate().catch((e) => {
    console.warn('Service worker registration failed:', e);
  }).finally(bootApp);
} else {
  bootApp();
}
