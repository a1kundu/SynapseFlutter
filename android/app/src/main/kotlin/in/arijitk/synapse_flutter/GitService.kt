package `in`.arijitk.synapse_flutter

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.api.ListBranchCommand
import org.eclipse.jgit.api.MergeResult
import org.eclipse.jgit.api.ResetCommand
import org.eclipse.jgit.api.CreateBranchCommand
import org.eclipse.jgit.diff.DiffFormatter
import org.eclipse.jgit.lib.PersonIdent
import org.eclipse.jgit.lib.Repository
import org.eclipse.jgit.transport.CredentialsProvider
import org.eclipse.jgit.transport.URIish
import org.eclipse.jgit.transport.UsernamePasswordCredentialsProvider
import org.eclipse.jgit.dircache.DirCacheIterator
import org.eclipse.jgit.treewalk.CanonicalTreeParser
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/**
 * Handles all Git operations via JGit, called from Flutter's MethodChannel.
 *
 * Each method receives a [MethodCall] and [MethodChannel.Result] and runs
 * the potentially blocking JGit work on [Dispatchers.IO].
 */
class GitService {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val dateFormat = ThreadLocal.withInitial {
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }
    }

    /** Route a method call to the appropriate handler. */
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        scope.launch {
            try {
                val response: Any = when (call.method) {
                    "init"          -> doInit(call)
                    "clone"         -> doClone(call)
                    "status"        -> doStatus(call)
                    "add"           -> doAdd(call)
                    "remove"        -> doRemove(call)
                    "commit"        -> doCommit(call)
                    "log"           -> doLog(call)
                    "diff"          -> doDiff(call)
                    "branch_list"   -> doBranchList(call)
                    "branch_create" -> doBranchCreate(call)
                    "branch_delete" -> doBranchDelete(call)
                    "branch_rename" -> doBranchRename(call)
                    "checkout"      -> doCheckout(call)
                    "merge"         -> doMerge(call)
                    "pull"          -> doPull(call)
                    "push"          -> doPush(call)
                    "remote_list"   -> doRemoteList(call)
                    "remote_add"    -> doRemoteAdd(call)
                    "remote_remove" -> doRemoteRemove(call)
                    "stash_create"  -> doStashCreate(call)
                    "stash_list"    -> doStashList(call)
                    "stash_apply"   -> doStashApply(call)
                    "stash_drop"    -> doStashDrop(call)
                    "tag_list"      -> doTagList(call)
                    "tag_create"    -> doTagCreate(call)
                    "tag_delete"    -> doTagDelete(call)
                    "reset"         -> doReset(call)
                    "clean"         -> doClean(call)
                    else -> throw IllegalArgumentException("Unknown git method: ${call.method}")
                }
                withContext(Dispatchers.Main) { result.success(response) }
            } catch (e: Exception) {
                val msg = e.message ?: e.toString()
                withContext(Dispatchers.Main) { result.error("GIT_ERROR", msg, null) }
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /** Open an existing repo at [path]. Uses Git.open() so close() releases the Repository. */
    private fun openRepo(path: String): Git {
        val dir = File(path)
        if (!File(dir, ".git").exists()) throw IllegalArgumentException("Not a git repository: $path")
        return Git.open(dir)
    }

    /** Build a [CredentialsProvider] from optional username/password args. */
    private fun credentials(call: MethodCall): CredentialsProvider? {
        val user = call.argument<String>("username")
        val pass = call.argument<String>("password") ?: call.argument<String>("token")
        return if (user != null && pass != null) {
            UsernamePasswordCredentialsProvider(user, pass)
        } else null
    }

    private fun requireArg(call: MethodCall, name: String): String {
        return call.argument<String>(name)
            ?: throw IllegalArgumentException("\"$name\" is required")
    }

    private fun formatPersonIdent(pi: PersonIdent): String {
        return "${pi.name} <${pi.emailAddress}> ${dateFormat.get().format(pi.getWhen())}"
    }

    // ── Init / Clone ────────────────────────────────────────────────────

    private fun doInit(call: MethodCall): String {
        val path = requireArg(call, "path")
        val bare = call.argument<Boolean>("bare") ?: false
        val dir = File(path)
        Git.init().setDirectory(dir).setBare(bare).call().close()
        return "Initialized ${if (bare) "bare " else ""}repository: $path"
    }

    private fun doClone(call: MethodCall): String {
        val url = requireArg(call, "url")
        val path = requireArg(call, "path")
        val branch = call.argument<String>("branch")
        val dir = File(path)

        val cmd = Git.cloneRepository()
            .setURI(url)
            .setDirectory(dir)
        if (branch != null) cmd.setBranch(branch)
        credentials(call)?.let { cmd.setCredentialsProvider(it) }
        val git = cmd.call()
        val head = git.repository.resolve("HEAD")?.name?.take(7) ?: "unknown"
        git.close()
        return "Cloned $url into $path (HEAD: $head)"
    }

    // ── Status ──────────────────────────────────────────────────────────

    private fun doStatus(call: MethodCall): Map<String, Any> {
        val path = requireArg(call, "path")
        val git = openRepo(path)
        try {
            val status = git.status().call()
            val branch = git.repository.branch ?: "(detached)"
            return mapOf(
                "branch" to branch,
                "is_clean" to status.isClean,
                "staged_added" to status.added.sorted(),
                "staged_changed" to status.changed.sorted(),
                "staged_removed" to status.removed.sorted(),
                "unstaged_modified" to status.modified.sorted(),
                "unstaged_deleted" to status.missing.sorted(),
                "untracked" to status.untracked.sorted(),
                "conflicting" to status.conflicting.sorted(),
            )
        } finally {
            git.close()
        }
    }

    // ── Add / Remove ────────────────────────────────────────────────────

    private fun doAdd(call: MethodCall): String {
        val path = requireArg(call, "path")
        val filepattern = call.argument<String>("filepattern") ?: "."
        val git = openRepo(path)
        try {
            git.add().addFilepattern(filepattern).call()
            return "Added: $filepattern"
        } finally {
            git.close()
        }
    }

    private fun doRemove(call: MethodCall): String {
        val path = requireArg(call, "path")
        val filepattern = requireArg(call, "filepattern")
        val cached = call.argument<Boolean>("cached") ?: false
        val git = openRepo(path)
        try {
            git.rm().addFilepattern(filepattern).setCached(cached).call()
            return if (cached) "Unstaged: $filepattern" else "Removed: $filepattern"
        } finally {
            git.close()
        }
    }

    // ── Commit ──────────────────────────────────────────────────────────

    private fun doCommit(call: MethodCall): String {
        val path = requireArg(call, "path")
        val message = requireArg(call, "message")
        val authorName = call.argument<String>("author_name")
        val authorEmail = call.argument<String>("author_email")
        val amend = call.argument<Boolean>("amend") ?: false
        val git = openRepo(path)
        try {
            val cmd = git.commit().setMessage(message).setAmend(amend)
            if (authorName != null && authorEmail != null) {
                cmd.setAuthor(authorName, authorEmail)
            }
            val rev = cmd.call()
            return "Committed: ${rev.id.name.take(7)} $message"
        } finally {
            git.close()
        }
    }

    // ── Log ─────────────────────────────────────────────────────────────

    private fun doLog(call: MethodCall): List<Map<String, String>> {
        val path = requireArg(call, "path")
        val maxCount = call.argument<Int>("max_count") ?: 20
        val git = openRepo(path)
        try {
            val log = git.log().setMaxCount(maxCount).call()
            return log.map { commit ->
                mapOf(
                    "hash" to commit.id.name,
                    "short_hash" to commit.id.name.take(7),
                    "message" to commit.fullMessage.trim(),
                    "author" to formatPersonIdent(commit.authorIdent),
                    "committer" to formatPersonIdent(commit.committerIdent),
                    "parents" to commit.parents.joinToString(",") { it.id.name.take(7) },
                )
            }
        } finally {
            git.close()
        }
    }

    // ── Diff ────────────────────────────────────────────────────────────

    private fun doDiff(call: MethodCall): String {
        val path = requireArg(call, "path")
        val staged = call.argument<Boolean>("staged") ?: false
        val git = openRepo(path)
        try {
            val repo = git.repository
            val out = ByteArrayOutputStream()
            val formatter = DiffFormatter(out)
            try {
                formatter.setRepository(repo)

                if (staged) {
                    // Diff index (staged) vs HEAD
                    val reader = repo.newObjectReader()
                    reader.use {
                        val headTree = CanonicalTreeParser()
                        val headId = repo.resolve("HEAD^{tree}")
                        if (headId != null) {
                            headTree.reset(it, headId)
                        }
                        val entries: List<org.eclipse.jgit.diff.DiffEntry> = formatter.scan(headTree, DirCacheIterator(repo.readDirCache()))
                        for (entry in entries) {
                            formatter.format(entry)
                        }
                    }
                } else {
                    // Diff working tree vs index
                    git.diff().setOutputStream(out).call()
                }
                formatter.flush()
            } finally {
                formatter.close()
            }
            val diffText = out.toString("UTF-8")
            return if (diffText.isBlank()) "No differences." else diffText.trimEnd()
        } finally {
            git.close()
        }
    }

    // ── Branch ──────────────────────────────────────────────────────────

    private fun doBranchList(call: MethodCall): Map<String, Any> {
        val path = requireArg(call, "path")
        val all = call.argument<Boolean>("all") ?: false
        val git = openRepo(path)
        try {
            val currentBranch = git.repository.branch ?: ""
            val mode = if (all) ListBranchCommand.ListMode.ALL else null
            val cmd = git.branchList()
            if (mode != null) cmd.setListMode(mode)
            val branches = cmd.call().map { ref ->
                val name = Repository.shortenRefName(ref.name)
                mapOf(
                    "name" to name,
                    "is_current" to (name == currentBranch),
                    "ref" to ref.name,
                    "hash" to (ref.objectId?.name?.take(7) ?: ""),
                )
            }
            return mapOf(
                "current" to currentBranch,
                "branches" to branches,
            )
        } finally {
            git.close()
        }
    }

    private fun doBranchCreate(call: MethodCall): String {
        val path = requireArg(call, "path")
        val name = requireArg(call, "name")
        val startPoint = call.argument<String>("start_point")
        val git = openRepo(path)
        try {
            val cmd = git.branchCreate().setName(name)
            if (startPoint != null) cmd.setStartPoint(startPoint)
            cmd.call()
            return "Created branch: $name"
        } finally {
            git.close()
        }
    }

    private fun doBranchDelete(call: MethodCall): String {
        val path = requireArg(call, "path")
        val name = requireArg(call, "name")
        val force = call.argument<Boolean>("force") ?: false
        val git = openRepo(path)
        try {
            git.branchDelete().setBranchNames(name).setForce(force).call()
            return "Deleted branch: $name"
        } finally {
            git.close()
        }
    }

    private fun doBranchRename(call: MethodCall): String {
        val path = requireArg(call, "path")
        val oldName = requireArg(call, "old_name")
        val newName = requireArg(call, "new_name")
        val git = openRepo(path)
        try {
            git.branchRename().setOldName(oldName).setNewName(newName).call()
            return "Renamed branch: $oldName -> $newName"
        } finally {
            git.close()
        }
    }

    // ── Checkout ─────────────────────────────────────────────────────────

    private fun doCheckout(call: MethodCall): String {
        val path = requireArg(call, "path")
        val name = requireArg(call, "name")
        val createBranch = call.argument<Boolean>("create_branch") ?: false
        val git = openRepo(path)
        try {
            val cmd = git.checkout().setName(name)
            if (createBranch) {
                cmd.setCreateBranch(true)
                cmd.setUpstreamMode(CreateBranchCommand.SetupUpstreamMode.TRACK)
            }
            cmd.call()
            return "Switched to${if (createBranch) " new" else ""} branch: $name"
        } finally {
            git.close()
        }
    }

    // ── Merge ───────────────────────────────────────────────────────────

    private fun doMerge(call: MethodCall): String {
        val path = requireArg(call, "path")
        val branch = requireArg(call, "branch")
        val git = openRepo(path)
        try {
            val ref = git.repository.findRef(branch)
                ?: throw IllegalArgumentException("Branch not found: $branch")
            val mergeResult = git.merge().include(ref).call()
            return when (mergeResult.mergeStatus) {
                MergeResult.MergeStatus.ALREADY_UP_TO_DATE -> "Already up to date."
                MergeResult.MergeStatus.FAST_FORWARD ->
                    "Fast-forward merge to ${mergeResult.newHead.name.take(7)}"
                MergeResult.MergeStatus.MERGED ->
                    "Merged ${branch} into current branch (${mergeResult.newHead.name.take(7)})"
                MergeResult.MergeStatus.CONFLICTING -> {
                    val conflicts = mergeResult.conflicts?.keys?.sorted()?.joinToString(", ") ?: ""
                    "Merge conflict! Conflicting files: $conflicts\nResolve conflicts and commit."
                }
                MergeResult.MergeStatus.FAILED ->
                    "Merge failed: ${mergeResult.failingPaths}"
                else -> "Merge result: ${mergeResult.mergeStatus}"
            }
        } finally {
            git.close()
        }
    }

    // ── Pull / Push ─────────────────────────────────────────────────────

    private fun doPull(call: MethodCall): String {
        val path = requireArg(call, "path")
        val remote = call.argument<String>("remote") ?: "origin"
        val branch = call.argument<String>("branch")
        val git = openRepo(path)
        try {
            val cmd = git.pull().setRemote(remote)
            if (branch != null) cmd.setRemoteBranchName(branch)
            credentials(call)?.let { cmd.setCredentialsProvider(it) }
            val pullResult = cmd.call()
            val fetchMsg = pullResult.fetchResult?.messages?.trim() ?: ""
            val mergeStatus = pullResult.mergeResult?.mergeStatus?.toString() ?: "unknown"
            return "Pull from $remote: $mergeStatus${if (fetchMsg.isNotEmpty()) "\n$fetchMsg" else ""}"
        } finally {
            git.close()
        }
    }

    private fun doPush(call: MethodCall): String {
        val path = requireArg(call, "path")
        val remote = call.argument<String>("remote") ?: "origin"
        val branch = call.argument<String>("branch")
        val force = call.argument<Boolean>("force") ?: false
        val pushTags = call.argument<Boolean>("tags") ?: false
        val git = openRepo(path)
        try {
            val cmd = git.push().setRemote(remote).setForce(force)
            if (branch != null) cmd.add(branch)
            if (pushTags) cmd.setPushTags()
            credentials(call)?.let { cmd.setCredentialsProvider(it) }
            val results = cmd.call()
            val buf = StringBuilder("Push to $remote:")
            for (pr in results) {
                for (update in pr.remoteUpdates) {
                    buf.append("\n  ${update.remoteName}: ${update.status}")
                }
                val msgs = pr.messages?.trim() ?: ""
                if (msgs.isNotEmpty()) buf.append("\n  $msgs")
            }
            return buf.toString()
        } finally {
            git.close()
        }
    }

    // ── Remote ──────────────────────────────────────────────────────────

    private fun doRemoteList(call: MethodCall): List<Map<String, String>> {
        val path = requireArg(call, "path")
        val git = openRepo(path)
        try {
            val config = git.repository.config
            val remoteNames = config.getSubsections("remote")
            return remoteNames.map { name ->
                mapOf(
                    "name" to name,
                    "url" to (config.getString("remote", name, "url") ?: ""),
                    "fetch" to (config.getString("remote", name, "fetch") ?: ""),
                )
            }
        } finally {
            git.close()
        }
    }

    private fun doRemoteAdd(call: MethodCall): String {
        val path = requireArg(call, "path")
        val name = requireArg(call, "name")
        val url = requireArg(call, "url")
        val git = openRepo(path)
        try {
            git.remoteAdd().setName(name).setUri(URIish(url)).call()
            return "Added remote: $name -> $url"
        } finally {
            git.close()
        }
    }

    private fun doRemoteRemove(call: MethodCall): String {
        val path = requireArg(call, "path")
        val name = requireArg(call, "name")
        val git = openRepo(path)
        try {
            git.remoteRemove().setRemoteName(name).call()
            return "Removed remote: $name"
        } finally {
            git.close()
        }
    }

    // ── Stash ───────────────────────────────────────────────────────────

    private fun doStashCreate(call: MethodCall): String {
        val path = requireArg(call, "path")
        val message = call.argument<String>("message")
        val includeUntracked = call.argument<Boolean>("include_untracked") ?: false
        val git = openRepo(path)
        try {
            val cmd = git.stashCreate().setIncludeUntracked(includeUntracked)
            if (message != null) cmd.setWorkingDirectoryMessage(message)
            val rev = cmd.call() ?: return "Nothing to stash."
            return "Stashed: ${rev.name.take(7)}${if (message != null) " ($message)" else ""}"
        } finally {
            git.close()
        }
    }

    private fun doStashList(call: MethodCall): List<Map<String, String>> {
        val path = requireArg(call, "path")
        val git = openRepo(path)
        try {
            val stashes = git.stashList().call()
            return stashes.mapIndexed { index, rev ->
                mapOf(
                    "index" to "stash@{$index}",
                    "hash" to rev.id.name.take(7),
                    "message" to rev.fullMessage.trim(),
                )
            }
        } finally {
            git.close()
        }
    }

    private fun doStashApply(call: MethodCall): String {
        val path = requireArg(call, "path")
        val stashRef = call.argument<String>("stash_ref") ?: "stash@{0}"
        val drop = call.argument<Boolean>("drop") ?: false
        val git = openRepo(path)
        try {
            git.stashApply().setStashRef(stashRef).call()
            if (drop) {
                // JGit stashDrop takes an index int
                val indexMatch = Regex("""stash@\{(\d+)\}""").find(stashRef)
                val stashIndex = indexMatch?.groupValues?.get(1)?.toIntOrNull() ?: 0
                git.stashDrop().setStashRef(stashIndex).call()
                return "Applied and dropped: $stashRef"
            }
            return "Applied: $stashRef"
        } finally {
            git.close()
        }
    }

    private fun doStashDrop(call: MethodCall): String {
        val path = requireArg(call, "path")
        val stashRef = call.argument<String>("stash_ref") ?: "stash@{0}"
        val git = openRepo(path)
        try {
            val indexMatch = Regex("""stash@\{(\d+)\}""").find(stashRef)
            val stashIndex = indexMatch?.groupValues?.get(1)?.toIntOrNull() ?: 0
            git.stashDrop().setStashRef(stashIndex).call()
            return "Dropped: $stashRef"
        } finally {
            git.close()
        }
    }

    // ── Tag ─────────────────────────────────────────────────────────────

    private fun doTagList(call: MethodCall): List<Map<String, String>> {
        val path = requireArg(call, "path")
        val git = openRepo(path)
        try {
            val tags = git.tagList().call()
            return tags.map { ref ->
                val name = Repository.shortenRefName(ref.name)
                mapOf(
                    "name" to name,
                    "ref" to ref.name,
                    "hash" to (ref.objectId?.name?.take(7) ?: ""),
                )
            }
        } finally {
            git.close()
        }
    }

    private fun doTagCreate(call: MethodCall): String {
        val path = requireArg(call, "path")
        val name = requireArg(call, "name")
        val message = call.argument<String>("message")
        val git = openRepo(path)
        try {
            val cmd = git.tag().setName(name)
            if (message != null) {
                cmd.setMessage(message)
                cmd.setAnnotated(true)
            } else {
                cmd.setAnnotated(false) // lightweight tag
            }
            cmd.call()
            return "Created tag: $name${if (message != null) " (annotated)" else " (lightweight)"}"
        } finally {
            git.close()
        }
    }

    private fun doTagDelete(call: MethodCall): String {
        val path = requireArg(call, "path")
        val name = requireArg(call, "name")
        val git = openRepo(path)
        try {
            git.tagDelete().setTags(name).call()
            return "Deleted tag: $name"
        } finally {
            git.close()
        }
    }

    // ── Reset / Clean ───────────────────────────────────────────────────

    private fun doReset(call: MethodCall): String {
        val path = requireArg(call, "path")
        val mode = call.argument<String>("mode") ?: "mixed"
        val ref = call.argument<String>("ref") ?: "HEAD"
        val git = openRepo(path)
        try {
            val resetMode = when (mode.lowercase()) {
                "soft"  -> ResetCommand.ResetType.SOFT
                "mixed" -> ResetCommand.ResetType.MIXED
                "hard"  -> ResetCommand.ResetType.HARD
                else    -> throw IllegalArgumentException(
                    "Invalid reset mode: $mode. Use soft, mixed, or hard."
                )
            }
            val result = git.reset().setMode(resetMode).setRef(ref).call()
            return "Reset ($mode) to $ref -> ${result.objectId?.name?.take(7) ?: ref}"
        } finally {
            git.close()
        }
    }

    private fun doClean(call: MethodCall): String {
        val path = requireArg(call, "path")
        val dirs = call.argument<Boolean>("directories") ?: false
        val force = call.argument<Boolean>("force") ?: false
        val dryRun = call.argument<Boolean>("dry_run") ?: false
        val git = openRepo(path)
        try {
            val cmd = git.clean()
                .setCleanDirectories(dirs)
                .setForce(force)
                .setDryRun(dryRun)
            val cleaned = cmd.call()
            return if (cleaned.isEmpty()) {
                "Nothing to clean."
            } else if (dryRun) {
                "Would remove:\n${cleaned.sorted().joinToString("\n") { "  $it" }}"
            } else {
                "Removed:\n${cleaned.sorted().joinToString("\n") { "  $it" }}"
            }
        } finally {
            git.close()
        }
    }
}
