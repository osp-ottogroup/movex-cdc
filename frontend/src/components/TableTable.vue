<template>
  <table class="table is-striped is-hoverable">
    <thead>
    <tr>
      <th>
        Tables
      </th>
    </tr>
    </thead>
    <tbody>
    <tr v-for="table in tables" :key="table.id">
      <td>{{ table.name }}</td>
    </tr>
    </tbody>
  </table>
</template>

<script>
export default {
  name: 'TableTable',
  props: {
    tables: { type: Array, default: () => [] },
  },
};
</script>
