module main

import fc_coordination_core as core
import json
import local_http_core as http_core
import net.http
import os
import project_line_guard
import time

const default_worth_it = 'C:/git/v_projects/contests/worth_it/future_caribbean_ai_buildathon'
const default_site = 'C:/git/websites/future_caribbean_ai_buildathon'
const default_port = 4173

struct StaticHandler {
	site_root string
}

fn main() {
	args := os.args[1..].filter(it != '--')
	cmd := if args.len == 0 { 'help' } else { args[0] }
	exit_code := match cmd {
		'generate' {
			run_generate(args[1..])
		}
		'qa' {
			run_qa(args[1..])
		}
		'form' {
			run_form(args[1..])
		}
		'serve' {
			run_serve(args[1..])
		}
		'help', '--help', '-h' {
			print_help()
		}
		else {
			eprintln('unknown command: ${cmd}')
			print_help()
			1
		}
	}

	if exit_code != 0 {
		exit(exit_code)
	}
}

fn run_generate(args []string) int {
	worth_it := flag_value(args, '--worth-it', default_worth_it)
	site := flag_value(args, '--site', default_site)
	os.mkdir_all(os.join_path(site, 'src', 'data')) or {
		eprintln(err.msg())
		return 1
	}
	os.mkdir_all(os.join_path(worth_it, 'docs')) or { return fail(err.msg()) }
	os.mkdir_all(os.join_path(worth_it, 'application')) or { return fail(err.msg()) }
	os.mkdir_all(os.join_path(worth_it, 'evidence')) or { return fail(err.msg()) }
	scenarios := core.scenario_catalog()
	write_text(os.join_path(site, 'src', 'data', 'scenarios.json'), json.encode_pretty(scenarios)) or {
		return fail(err.msg())
	}
	write_text(os.join_path(site, 'src', 'data', 'build_plan.json'),
		json.encode_pretty(core.build_plan())) or { return fail(err.msg()) }
	write_text(os.join_path(worth_it, 'docs', 'competitive_edge.md'),
		core.competitive_edge_markdown()) or { return fail(err.msg()) }
	write_text(os.join_path(worth_it, 'docs', 'production_runbook.md'), core.runbook_markdown()) or {
		return fail(err.msg())
	}
	write_text(os.join_path(worth_it, 'application', 'future_caribbean.answers.generated.json'),
		json.encode_pretty(core.default_answers())) or { return fail(err.msg()) }
	assets := ['Vue3 CDN + SFC demo', 'Vlang coordination core', 'Submission dry-run',
		'Evidence pack']
	report := core.readiness_report('0.8.0', assets, ['Applicant identity', 'Loom video',
		'External deployment URL'])
	write_text(os.join_path(worth_it, 'evidence', 'readiness_report.json'),
		json.encode_pretty(report)) or { return fail(err.msg()) }
	println('generated site data, application answers and evidence pack')
	return 0
}

fn run_qa(args []string) int {
	worth_it := flag_value(args, '--worth-it', default_worth_it)
	site := flag_value(args, '--site', default_site)
	product := os.dir(os.dir(os.dir(@FILE)))
	mut failures := []string{}
	for target in [worth_it, site, product] {
		if !os.exists(target) {
			failures << 'missing target: ${target}'
			continue
		}
		report := project_line_guard.audit_line_caps(project_line_guard.GuardOptions{
			root:       target
			limit:      600
			near_limit: 560
		})
		for item in report.failures {
			failures << '${item.rel} has ${item.lines} lines'
		}
	}
	if failures.len > 0 {
		eprintln('qa failed:')
		for item in failures {
			eprintln('- ${item}')
		}
		return 2
	}
	println('qa passed: line caps and target presence ok')
	return 0
}

fn run_form(args []string) int {
	worth_it := flag_value(args, '--worth-it', default_worth_it)
	answers_path := flag_value(args, '--answers', os.join_path(worth_it, 'application',
		'future_caribbean.answers.generated.json'))
	target := flag_value(args, '--target', 'https://futurecaribbean.com/')
	dry_run := has_flag(args, '--dry-run') || !has_flag(args, '--submit')
	allow_placeholders := has_flag(args, '--allow-placeholders')
	answers := load_answers(answers_path) or { core.default_answers() }
	payload := core.build_payload(answers)
	validation := core.validate_answers(answers, allow_placeholders)
	os.mkdir_all(os.join_path(worth_it, 'evidence')) or {}
	preview := {
		'target':    target
		'dry_run':   dry_run.str()
		'ok':        validation.ok.str()
		'generated': time.now().format_rfc3339()
		'blockers':  validation.blockers.join(' | ')
		'warnings':  validation.warnings.join(' | ')
		'payload':   json.encode(core.redact_payload(payload))
	}
	write_text(os.join_path(worth_it, 'evidence', 'application_payload_preview_v.json'),
		json.encode_pretty(preview)) or { return fail(err.msg()) }
	if !validation.ok {
		eprintln('application payload is not submit-ready')
		for item in validation.blockers {
			eprintln('- ${item}')
		}
		return if dry_run { 0 } else { 2 }
	}
	if dry_run {
		println('dry-run passed: V payload preview written')
		return 0
	}
	if os.getenv('APPLICATION_CONSENT_TO_SUBMIT') != 'yes' {
		eprintln('blocked: set APPLICATION_CONSENT_TO_SUBMIT=yes for real external submission')
		return 3
	}
	mut header := http.new_header()
	header.set(.content_type, 'application/x-www-form-urlencoded')
	response := http.fetch(
		url:    target
		method: .post
		header: header
		data:   core.encode_form(payload)
	) or { return fail(err.msg()) }
	receipt_path := os.join_path(worth_it, 'evidence',
		'submission_receipt_v_${time.now().unix()}.json')
	receipt := {
		'target':       target
		'status':       response.status_code.str()
		'ok':           (response.status_code >= 200 && response.status_code < 300).str()
		'submitted_at': time.now().format_rfc3339()
	}
	write_text(receipt_path, json.encode_pretty(receipt)) or { return fail(err.msg()) }
	println('submission receipt: ${receipt_path}')
	return if response.status_code >= 200 && response.status_code < 300 { 0 } else { 4 }
}

fn run_serve(args []string) int {
	site := flag_value(args, '--site', default_site)
	port := flag_value(args, '--port', default_port.str()).int()
	if !os.exists(os.join_path(site, 'index.html')) {
		eprintln('site index not found: ${site}')
		return 2
	}
	println('serving ${site} at http://127.0.0.1:${port}')
	mut server := http.Server{
		addr:                 '127.0.0.1:${port}'
		handler:              StaticHandler{
			site_root: site
		}
		show_startup_message: false
	}
	server.listen_and_serve()
	return 0
}

fn (handler StaticHandler) handle(req http.Request) http.Response {
	path := http_core.request_path(req.url)
	mut rel := path.trim_left('/')
	if rel == '' {
		rel = 'index.html'
	}
	if rel.contains('..') || os.is_abs_path(rel) {
		return http_core.forbidden_response(security_headers())
	}
	full_path := os.join_path(handler.site_root, rel)
	if os.exists(full_path) && os.is_file(full_path) {
		return http_core.file_response(full_path, cache_for(rel), security_headers())
	}
	return http_core.file_response(os.join_path(handler.site_root, 'index.html'), 'no-cache',
		security_headers())
}

fn load_answers(path string) !map[string]string {
	raw := os.read_file(path)!
	return json.decode(map[string]string, raw)!
}

fn write_text(path string, content string) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, content)!
}

fn flag_value(args []string, name string, fallback string) string {
	for i, item in args {
		if item == name && i + 1 < args.len {
			return args[i + 1]
		}
		prefix := name + '='
		if item.starts_with(prefix) {
			return item[prefix.len..]
		}
	}
	return fallback
}

fn has_flag(args []string, name string) bool {
	return args.any(it == name)
}

fn cache_for(rel string) string {
	if rel.ends_with('.js') || rel.ends_with('.vue') || rel.ends_with('.css')
		|| rel.ends_with('.json') {
		return 'no-cache'
	}
	return 'public, max-age=300'
}

fn security_headers() http_core.LocalSecurityHeaders {
	return http_core.LocalSecurityHeaders{
		content_security_policy: "default-src 'self' https://unpkg.com https://cdn.jsdelivr.net; script-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; connect-src 'self'; img-src 'self' data:; font-src 'self' data:"
	}
}

fn fail(message string) int {
	eprintln(message)
	return 1
}

fn print_help() int {
	println('fcbuild commands: generate | qa | form | serve')
	return 0
}
