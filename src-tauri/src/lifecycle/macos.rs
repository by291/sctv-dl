use std::sync::{Arc, OnceLock};

use objc2::{
    MainThreadMarker, ffi,
    runtime::{AnyClass, AnyObject, Imp, Sel},
    sel,
};
use objc2_app_kit::{NSApplication, NSApplicationTerminateReply};
use tauri::{AppHandle, Manager};

use super::{ExitController, request_exit};

static APP: OnceLock<AppHandle> = OnceLock::new();

unsafe extern "C-unwind" fn should_terminate(
    _delegate: &AnyObject,
    _selector: Sel,
    _sender: &NSApplication,
) -> NSApplicationTerminateReply {
    let Some(app) = APP.get() else {
        return NSApplicationTerminateReply::TerminateCancel;
    };
    if app.state::<Arc<ExitController>>().committed() {
        return NSApplicationTerminateReply::TerminateNow;
    }

    request_exit(app);
    NSApplicationTerminateReply::TerminateCancel
}

fn add_termination_method(class: &AnyClass) -> tauri::Result<()> {
    let selector = sel!(applicationShouldTerminate:);
    if class.instance_method(selector).is_some() {
        return Err(
            std::io::Error::other("application delegate already handles termination").into(),
        );
    }

    // SAFETY: AppKit invokes this delegate method on the main thread. The callback
    // exactly matches its ABI: NSUInteger return, receiver, selector, NSApplication.
    // Apple Silicon uses a 64-bit NSUInteger. Add only a missing method;
    // preserve TAO's delegate, its ivars, and every existing implementation.
    let added = unsafe {
        let implementation: Imp = std::mem::transmute::<
            unsafe extern "C-unwind" fn(
                &AnyObject,
                Sel,
                &NSApplication,
            ) -> NSApplicationTerminateReply,
            Imp,
        >(should_terminate);
        ffi::class_addMethod(
            class as *const AnyClass as *mut AnyClass,
            selector,
            implementation,
            c"Q@:@".as_ptr(),
        )
    };
    if !added.as_bool() {
        return Err(
            std::io::Error::other("could not install application termination guard").into(),
        );
    }

    Ok(())
}

pub fn install(app: &AppHandle) -> tauri::Result<()> {
    let main = MainThreadMarker::new()
        .ok_or_else(|| std::io::Error::other("termination guard requires the main thread"))?;
    let application = NSApplication::sharedApplication(main);
    let delegate = application
        .delegate()
        .ok_or_else(|| std::io::Error::other("application delegate is missing"))?;

    APP.set(app.clone())
        .map_err(|_| std::io::Error::other("termination guard already installed"))?;
    let delegate: &AnyObject = (*delegate).as_ref();
    add_termination_method(delegate.class())
}

#[cfg(test)]
mod tests {
    use objc2::runtime::ClassBuilder;

    use super::*;

    #[test]
    fn termination_guard_adds_only_the_missing_selector() {
        let class = ClassBuilder::new(
            c"SctvTerminationGuardTest",
            AnyClass::get(c"NSObject").unwrap(),
        )
        .unwrap()
        .register();
        assert!(
            class
                .instance_method(sel!(applicationShouldTerminate:))
                .is_none()
        );

        add_termination_method(class).unwrap();

        assert!(
            class
                .instance_method(sel!(applicationShouldTerminate:))
                .is_some()
        );
        assert!(add_termination_method(class).is_err());
    }
}
