//! Signal Handling & Fallback State Machine Simulation
//!
//! Evaluates signalfd vs. fallback self-pipe behavior required for
//! cross-kernel compatibility (Linux 4.4 legacy vs Linux 6.18 modern).

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SignalMechanism {
    Signalfd,
    FallbackPipe,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UnixSignal {
    SigInt = 2,
    SigTerm = 15,
    SigHup = 1,
    SigUsr1 = 10,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SignalEngineError {
    SyscallUnsupported(i32),
    SignalNotAllowed(i32),
    AlreadyTerminated,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SignalEngine {
    pub mechanism: SignalMechanism,
    pub is_active: bool,
    pub termination_requested: bool,
    pub received_signals: Vec<UnixSignal>,
}

impl SignalEngine {
    /// Initialize with simulated syscall outcome
    /// syscall_errno: 0 for success, 38 for ENOSYS, 22 for EINVAL
    pub fn new_with_simulation(syscall_errno: i32) -> Result<Self, SignalEngineError> {
        if syscall_errno == 0 {
            Ok(Self {
                mechanism: SignalMechanism::Signalfd,
                is_active: true,
                termination_requested: false,
                received_signals: Vec::new(),
            })
        } else if syscall_errno == 38 || syscall_errno == 22 {
            // Fallback path activates cleanly
            Ok(Self {
                mechanism: SignalMechanism::FallbackPipe,
                is_active: true,
                termination_requested: false,
                received_signals: Vec::new(),
            })
        } else {
            Err(SignalEngineError::SyscallUnsupported(syscall_errno))
        }
    }

    pub fn dispatch_signal(&mut self, sig: UnixSignal) -> Result<(), SignalEngineError> {
        if self.termination_requested {
            return Err(SignalEngineError::AlreadyTerminated);
        }

        self.received_signals.push(sig);
        match sig {
            UnixSignal::SigInt | UnixSignal::SigTerm => {
                self.termination_requested = true;
                self.is_active = false;
            }
            UnixSignal::SigHup => {
                // SIGHUP triggers re-read configuration
            }
            UnixSignal::SigUsr1 => {
                // SIGUSR1 dumps state
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_signalfd_native_success() {
        let mut engine = SignalEngine::new_with_simulation(0).expect("native init failed");
        assert_eq!(engine.mechanism, SignalMechanism::Signalfd);
        assert!(engine.is_active);

        engine.dispatch_signal(UnixSignal::SigHup).unwrap();
        assert!(engine.is_active);
        assert!(!engine.termination_requested);

        engine.dispatch_signal(UnixSignal::SigTerm).unwrap();
        assert!(!engine.is_active);
        assert!(engine.termination_requested);
    }

    #[test]
    fn test_signalfd_enosys_fallback() {
        // Simulated ENOSYS (errno 38)
        let mut engine = SignalEngine::new_with_simulation(38).expect("fallback init failed");
        assert_eq!(engine.mechanism, SignalMechanism::FallbackPipe);
        assert!(engine.is_active);

        engine.dispatch_signal(UnixSignal::SigInt).unwrap();
        assert!(!engine.is_active);
        assert!(engine.termination_requested);
    }

    #[test]
    fn test_signalfd_einval_fallback() {
        // Simulated EINVAL (errno 22)
        let engine = SignalEngine::new_with_simulation(22).expect("fallback init failed");
        assert_eq!(engine.mechanism, SignalMechanism::FallbackPipe);
        assert!(engine.is_active);
    }

    #[test]
    fn test_syscall_unexpected_error() {
        // Simulated EPERM (errno 1)
        let res = SignalEngine::new_with_simulation(1);
        assert_eq!(res, Err(SignalEngineError::SyscallUnsupported(1)));
    }

    #[test]
    fn test_reject_signal_after_termination() {
        let mut engine = SignalEngine::new_with_simulation(0).unwrap();
        engine.dispatch_signal(UnixSignal::SigTerm).unwrap();
        assert_eq!(
            engine.dispatch_signal(UnixSignal::SigInt),
            Err(SignalEngineError::AlreadyTerminated)
        );
    }
}
