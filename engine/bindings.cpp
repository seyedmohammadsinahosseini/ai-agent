// bindings.cpp
// Exposes the C++ engine (risk_classifier + pty_session) to Python via
// pybind11. Compiles into a native Python module: aiterm_engine

#include <pybind11/pybind11.h>
#include <pybind11/functional.h>
#include "risk_classifier.hpp"
#include "pty_session.hpp"

namespace py = pybind11;
using namespace aiterm;

// Wraps a py::object so it's safe to destroy from any thread (background
// native threads call/drop these callbacks, and pybind11 objects must only
// ever be incref'd/decref'd while holding the GIL).
static std::shared_ptr<py::object> make_gil_safe(py::object obj) {
    return std::shared_ptr<py::object>(
        new py::object(std::move(obj)),
        [](py::object* p) {
            py::gil_scoped_acquire acquire;
            delete p;
        });
}

PYBIND11_MODULE(aiterm_engine, m) {
    m.doc() = "AI Terminal native engine (risk classification + pty execution)";

    py::enum_<RiskLevel>(m, "RiskLevel")
        .value("SAFE", RiskLevel::SAFE)
        .value("CONFIRM", RiskLevel::CONFIRM)
        .value("DANGEROUS", RiskLevel::DANGEROUS)
        .value("BLOCKED", RiskLevel::BLOCKED);

    py::class_<ClassificationResult>(m, "ClassificationResult")
        .def_readonly("level", &ClassificationResult::level)
        .def_readonly("reason", &ClassificationResult::reason)
        .def_readonly("human_reason", &ClassificationResult::human_reason);

    py::class_<RiskClassifier>(m, "RiskClassifier")
        .def(py::init<>())
        .def("classify", &RiskClassifier::classify, py::arg("command"));

    py::class_<ExecResult>(m, "ExecResult")
        .def_readonly("output", &ExecResult::output)
        .def_readonly("exit_code", &ExecResult::exit_code);

    py::class_<PtySession>(m, "PtySession")
        .def_static("run", [](const std::string& command, const std::string& working_dir,
                               py::object on_chunk, int timeout_seconds) {
            std::shared_ptr<py::object> safe_obj;
            std::function<void(const std::string&)> cb = nullptr;
            if (!on_chunk.is_none()) {
                safe_obj = make_gil_safe(on_chunk);
                cb = [safe_obj](const std::string& s) {
                    py::gil_scoped_acquire acquire;
                    (*safe_obj)(s);
                };
            }
            py::gil_scoped_release release;
            return PtySession::run_in_dir(command, working_dir, cb, timeout_seconds);
        }, py::arg("command"), py::arg("working_dir") = "", py::arg("on_chunk") = py::none(),
           py::arg("timeout_seconds") = 30)

        .def_static("start_async", [](int64_t execution_id, const std::string& command,
                                       const std::string& working_dir,
                                       py::object on_chunk, py::object on_done, int timeout_seconds) {
            std::function<void(const std::string&)> chunk_cb = nullptr;
            if (!on_chunk.is_none()) {
                auto safe_obj = make_gil_safe(on_chunk);
                chunk_cb = [safe_obj](const std::string& s) {
                    py::gil_scoped_acquire acquire;
                    (*safe_obj)(s);
                };
            }
            std::function<void(int)> done_cb = nullptr;
            if (!on_done.is_none()) {
                auto safe_obj = make_gil_safe(on_done);
                done_cb = [safe_obj](int code) {
                    py::gil_scoped_acquire acquire;
                    (*safe_obj)(code);
                };
            }
            PtySession::start_async_in_dir(execution_id, command, working_dir, chunk_cb, done_cb, timeout_seconds);
        }, py::arg("execution_id"), py::arg("command"), py::arg("working_dir") = "",
           py::arg("on_chunk") = py::none(), py::arg("on_done") = py::none(),
           py::arg("timeout_seconds") = 120)

        .def_static("kill_execution", &PtySession::kill_execution, py::arg("execution_id"));
}
