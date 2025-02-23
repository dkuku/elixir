# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2021 The Elixir Team
# SPDX-FileCopyrightText: 2012 Plataformatec

defmodule Record.Extractor do
  @moduledoc false

  def extract(name, opts) do
    extract_record(name, from_or_from_lib_file(opts))
  end

  def extract_all(opts) do
    extract_all_records(from_or_from_lib_file(opts))
  end

  defp from_or_from_lib_file(opts) do
    cond do
      file = opts[:from] ->
        {from_file(file), Keyword.delete(opts, :from)}

      file = opts[:from_lib] ->
        {from_lib_file(file), Keyword.delete(opts, :from_lib)}

      true ->
        raise ArgumentError, "expected :from or :from_lib to be given as option"
    end
  end

  # Find file using the same lookup as the *include* attribute from Erlang modules.
  defp from_file(file) do
    file = String.to_charlist(file)

    case :code.where_is_file(file) do
      :non_existing -> file
      realfile -> realfile
    end
  end

  # Find file using the same lookup as the *include_lib* attribute from Erlang modules.
  defp from_lib_file(file) do
    [app | path] = :filename.split(String.to_charlist(file))

    case :code.lib_dir(List.to_atom(app)) do
      {:error, _} ->
        raise ArgumentError, "lib file #{file} could not be found"

      libpath ->
        :filename.join([libpath | path])
    end
  end

  # Retrieve the record with the given name from the given file
  defp extract_record(name, {file, opts}) do
    form = read_file(file, opts)
    records = extract_records(form)

    if record = List.keyfind(records, name, 0) do
      parse_record(record, form)
    else
      raise ArgumentError,
            "no record #{name} found at #{file}. Or the record does not exist or " <>
              "its entry is malformed or depends on other include files"
    end
  end

  # Retrieve all records from the given file
  defp extract_all_records({file, opts}) do
    form = read_file(file, opts)
    records = extract_records(form)
    for rec = {name, _fields} <- records, do: {name, parse_record(rec, form)}
  end

  # Parse the given file and extract all existent records.
  defp extract_records(form) do
    for {:attribute, _, :record, record} <- form, do: record
  end

  # Read a file and return its abstract syntax form that also
  # includes record but with macros and other attributes expanded,
  # such as "-include(...)" and "-include_lib(...)". This is done
  # by using Erlang's epp.
  defp read_file(file, opts) do
    case :epp.parse_file(file, opts) do
      {:ok, form} ->
        form

      other ->
        raise "error parsing file #{file}, got: #{inspect(other)}"
    end
  end

  # Parse a tuple with name and fields and returns a
  # list of tuples where the first element is the field
  # and the second is its default value.
  defp parse_record({_name, fields}, form) do
    cons = List.foldr(fields, {nil, 0}, fn f, acc -> {:cons, 0, parse_field(f), acc} end)
    eval_record(cons, form)
  end

  defp parse_field({:typed_record_field, record_field, _type}) do
    parse_field(record_field)
  end

  defp parse_field({:record_field, _, key}) do
    {:tuple, 0, [key, {:atom, 0, :undefined}]}
  end

  defp parse_field({:record_field, _, key, value}) do
    {:tuple, 0, [key, value]}
  end

  defp eval_record(cons, form) do
    form = form ++ [{:function, 0, :hello, 0, [{:clause, 0, [], [], [cons]}]}]

    {:function, 0, :hello, 0, [{:clause, 0, [], [], [record_ast]}]} =
      :erl_expand_records.module(form, []) |> List.last()

    {:value, record, _} = :erl_eval.expr(record_ast, [])
    record
  end
end
