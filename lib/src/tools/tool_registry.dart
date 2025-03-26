import 'dart:async';
import '../exceptions.dart';
import '../logging/logger.dart';
import 'tool.dart';
import 'tool_chain.dart';

class ToolRegistry {
  static final Map<String, Tool> _tools = {};
  static final Map<String, ToolChain> _chains = {};
  static final Map<String, Set<Tool>> _taggedTools = {};
  static final Map<String, Set<ToolChain>> _taggedChains = {};
  static MurmurationLogger? _logger;

  static void initialize(MurmurationLogger logger) {
    _logger = logger;
  }

  static void register(Tool tool) {
    if (_tools.containsKey(tool.name)) {
      throw InvalidConfigurationException(
        'Tool with name ${tool.name} is already registered',
      );
    }

    _tools[tool.name] = tool;
    for (final tag in tool.tags) {
      _taggedTools.putIfAbsent(tag, () => {}).add(tool);
    }

    _logger?.info(
      'Registered tool: ${tool.name}',
      metadata: {
        'tool': tool.name,
        'tags': tool.tags,
        'requiresAuth': tool.requiresAuth,
      },
    );
  }

  static void registerChain(ToolChain chain) {
    if (_chains.containsKey(chain.name)) {
      throw InvalidConfigurationException(
        'Chain with name ${chain.name} is already registered',
      );
    }

    // Validate that all tools in the chain are registered
    for (final tool in chain.tools) {
      if (!_tools.containsKey(tool.name)) {
        throw InvalidConfigurationException(
          'Tool ${tool.name} in chain ${chain.name} is not registered',
        );
      }
    }

    _chains[chain.name] = chain;
    for (final tag in chain.tags) {
      _taggedChains.putIfAbsent(tag, () => {}).add(chain);
    }

    _logger?.info(
      'Registered chain: ${chain.name}',
      metadata: {
        'chain': chain.name,
        'tools': chain.tools.map((t) => t.name).toList(),
        'tags': chain.tags,
        'requiresAuth': chain.requiresAuth,
      },
    );
  }

  static void unregister(String name) {
    final tool = _tools.remove(name);
    if (tool != null) {
      for (final tag in tool.tags) {
        _taggedTools[tag]?.remove(tool);
        if (_taggedTools[tag]?.isEmpty ?? false) {
          _taggedTools.remove(tag);
        }
      }

      _logger?.info(
        'Unregistered tool: $name',
        metadata: {'tool': name},
      );
    }

    final chain = _chains.remove(name);
    if (chain != null) {
      for (final tag in chain.tags) {
        _taggedChains[tag]?.remove(chain);
        if (_taggedChains[tag]?.isEmpty ?? false) {
          _taggedChains.remove(tag);
        }
      }

      _logger?.info(
        'Unregistered chain: $name',
        metadata: {'chain': name},
      );
    }
  }

  static Tool? getTool(String name) {
    final tool = _tools[name];
    if (tool != null) {
      _logger?.debug(
        'Retrieved tool: $name',
        metadata: {'tool': name},
      );
    }
    return tool;
  }

  static ToolChain? getChain(String name) {
    final chain = _chains[name];
    if (chain != null) {
      _logger?.debug(
        'Retrieved chain: $name',
        metadata: {'chain': name},
      );
    }
    return chain;
  }

  static Set<Tool> getToolsByTag(String tag) {
    final tools = _taggedTools[tag] ?? {};
    _logger?.debug(
      'Retrieved tools by tag: $tag',
      metadata: {
        'tag': tag,
        'count': tools.length,
        'tools': tools.map((t) => t.name).toList(),
      },
    );
    return tools;
  }

  static Set<ToolChain> getChainsByTag(String tag) {
    final chains = _taggedChains[tag] ?? {};
    _logger?.debug(
      'Retrieved chains by tag: $tag',
      metadata: {
        'tag': tag,
        'count': chains.length,
        'chains': chains.map((c) => c.name).toList(),
      },
    );
    return chains;
  }

  static List<Tool> getAllTools() {
    final tools = _tools.values.toList();
    _logger?.debug(
      'Retrieved all tools',
      metadata: {'count': tools.length},
    );
    return tools;
  }

  static List<ToolChain> getAllChains() {
    final chains = _chains.values.toList();
    _logger?.debug(
      'Retrieved all chains',
      metadata: {'count': chains.length},
    );
    return chains;
  }

  static Set<String> getAllTags() {
    final tags = {..._taggedTools.keys, ..._taggedChains.keys};
    _logger?.debug(
      'Retrieved all tags',
      metadata: {'count': tags.length, 'tags': tags.toList()},
    );
    return tags;
  }

  static bool hasTool(String name) => _tools.containsKey(name);

  static bool hasChain(String name) => _chains.containsKey(name);

  static void clear() {
    _tools.clear();
    _chains.clear();
    _taggedTools.clear();
    _taggedChains.clear();
    _logger?.info('Cleared all tools and chains');
  }

  static Map<String, dynamic> getStats() {
    return {
      'toolCount': _tools.length,
      'chainCount': _chains.length,
      'tagCount': getAllTags().length,
      'toolsByTag': Map.fromEntries(
        _taggedTools.entries.map((e) => MapEntry(e.key, e.value.length)),
      ),
      'chainsByTag': Map.fromEntries(
        _taggedChains.entries.map((e) => MapEntry(e.key, e.value.length)),
      ),
    };
  }
} 