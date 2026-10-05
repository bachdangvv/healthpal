use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

use serde_json::json;

use crate::runtime;
use crate::types::{AssessmentError, AssessmentRequest};

fn to_cstring(value: String) -> *mut c_char {
    CString::new(value.replace('\0', "")).map_or(ptr::null_mut(), CString::into_raw)
}

fn error_json(error: AssessmentError) -> String {
    match error {
        AssessmentError::InvalidRequest { code, message } => json!({
            "ok": false,
            "error": {"kind": "invalidRequest", "code": code, "message": message}
        })
        .to_string(),
        AssessmentError::Model { message } => json!({
            "ok": false,
            "error": {"kind": "model", "code": "model_error", "message": message}
        })
        .to_string(),
        AssessmentError::Internal { message } => json!({
            "ok": false,
            "error": {"kind": "internal", "code": "internal_error", "message": message}
        })
        .to_string(),
    }
}

fn ok_json(value: impl serde::Serialize) -> String {
    match serde_json::to_value(value) {
        Ok(payload) => json!({"ok": true, "result": payload}).to_string(),
        Err(err) => error_json(AssessmentError::Internal {
            message: format!("failed to serialize result: {err}"),
        }),
    }
}

/// Initializes the native library. Returns 0 on success.
#[no_mangle]
pub extern "C" fn healthpal_init() -> i32 {
    match runtime::init() {
        Ok(_) => 0,
        Err(_) => 1,
    }
}

#[no_mangle]
pub extern "C" fn healthpal_model_info_json() -> *mut c_char {
    let payload = match runtime::model_info() {
        Ok(info) => ok_json(info),
        Err(err) => error_json(err),
    };
    to_cstring(payload)
}

#[no_mangle]
pub extern "C" fn healthpal_assess_json(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return to_cstring(error_json(AssessmentError::invalid(
            "invalid_request",
            "request JSON pointer was null",
        )));
    }
    let raw = unsafe { CStr::from_ptr(request_json) };
    let text = match raw.to_str() {
        Ok(text) => text,
        Err(err) => {
            return to_cstring(error_json(AssessmentError::invalid(
                "invalid_request",
                format!("request JSON was not UTF-8: {err}"),
            )));
        }
    };
    let request: AssessmentRequest = match serde_json::from_str(text) {
        Ok(request) => request,
        Err(err) => {
            return to_cstring(error_json(AssessmentError::invalid(
                "invalid_request",
                format!("failed to parse AssessmentRequest: {err}"),
            )));
        }
    };
    let payload = match runtime::assess(request) {
        Ok(result) => ok_json(result),
        Err(err) => error_json(err),
    };
    to_cstring(payload)
}

#[no_mangle]
pub extern "C" fn healthpal_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}
